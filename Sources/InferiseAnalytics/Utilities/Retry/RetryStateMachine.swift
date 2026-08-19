import Foundation

public class RetryStateMachine {
    private let config: HttpConfig
    private let timeProvider: TimeProvider

    public init(config: HttpConfig, timeProvider: TimeProvider = SystemTimeProvider()) {
        self.config = config
        self.timeProvider = timeProvider
    }

    private var isLegacyMode: Bool {
        !self.config.rateLimitConfig.enabled && !self.config.backoffConfig.enabled
    }

    public func handleResponse(state: RetryState, response: ResponseInfo) -> RetryState {
        // Success: clear metadata
        if response.statusCode >= 200 && response.statusCode < 300 {
            var newState = state
            newState.pipelineState = .ready
            newState.waitUntilTime = nil
            newState.globalRetryCount = 0
            newState.batchMetadata.removeValue(forKey: response.batchFile)
            return newState
        }

        // 429 rate limiting
        if response.statusCode == 429 {
            if self.config.rateLimitConfig.enabled {
                let currentTime = response.currentTime
                return self.handleRateLimitResponse(state: state, response: response, currentTime: currentTime)
            }
            // Rate limit handling disabled: drop the batch (don't fall through to backoff)
            var newState = state
            newState.batchMetadata.removeValue(forKey: response.batchFile)
            return newState
        }

        // Exponential backoff for retryable errors
        let behavior = self.resolveStatusCodeBehavior(code: response.statusCode)
        if behavior == .retry {
            let currentTime = response.currentTime
            // If server provided Retry-After, treat as pipeline-level rate limit regardless of status code
            if response.retryAfterSeconds != nil && self.config.rateLimitConfig.enabled {
                return self.handleRateLimitResponse(state: state, response: response, currentTime: currentTime)
            }
            if self.config.backoffConfig.enabled {
                return self.handleRetryableError(state: state, response: response, currentTime: currentTime)
            }
        }

        // Drop non-retryable errors, or retryable errors when both configs are disabled
        var newState = state
        newState.batchMetadata.removeValue(forKey: response.batchFile)
        return newState
    }

    public func shouldUploadBatch(
        state: RetryState,
        batchFile: String
    ) -> (UploadDecision, RetryState) {
        // Legacy mode: skip all smart retry logic
        if self.isLegacyMode {
            return (.proceed, state)
        }

        let currentTime = self.timeProvider.now()

        // Check 1: Global rate limiting
        if state.isRateLimited(currentTime: currentTime) {
            return (.skipAllBatches, state)
        }

        // Clear stale rate limit state if it has expired
        var clearedState = state
        if state.pipelineState == .rateLimited,
           let waitTime = state.waitUntilTime,
           currentTime >= waitTime {
            clearedState.pipelineState = .ready
            clearedState.waitUntilTime = nil
        }

        // Check 2: Global rate limit retry count
        if self.config.rateLimitConfig.enabled &&
            clearedState.globalRetryCount >= self.config.rateLimitConfig.maxRetryCount {
            var dropState = clearedState
            dropState.globalRetryCount = 0
            dropState.batchMetadata.removeValue(forKey: batchFile)
            return (.dropBatch(reason: .maxRetriesExceeded), dropState)
        }

        // Check 3: Per-batch metadata
        guard let metadata = clearedState.batchMetadata[batchFile] else {
            return (.proceed, clearedState)
        }

        // Check retry count limit
        if self.config.backoffConfig.enabled &&
            metadata.failureCount >= self.config.backoffConfig.maxRetryCount {
            var dropState = clearedState
            dropState.batchMetadata.removeValue(forKey: batchFile)
            return (.dropBatch(reason: .maxRetriesExceeded), dropState)
        }

        // Check duration limit
        if self.config.backoffConfig.enabled &&
            metadata.exceedsMaxDuration(currentTime: currentTime, maxDuration: TimeInterval(self.config.backoffConfig.maxTotalBackoffDuration)) {
            var dropState = clearedState
            dropState.batchMetadata.removeValue(forKey: batchFile)
            return (.dropBatch(reason: .maxDurationExceeded), dropState)
        }

        // Check if backoff time has passed
        if self.config.backoffConfig.enabled && !metadata.shouldRetry(currentTime: currentTime) {
            return (.skipThisBatch, clearedState)
        }

        return (.proceed, clearedState)
    }

    public func getRetryCount(state: RetryState, batchFile: String) -> Int {
        let batchRetryCount = state.batchMetadata[batchFile]?.failureCount ?? 0
        return max(batchRetryCount, state.globalRetryCount)
    }

    /// Returns true if the given status code should result in the batch being dropped (not retried).
    public func shouldDropBatch(statusCode: Int) -> Bool {
        if self.isLegacyMode {
            return false
        }

        // 429 with rate limit handling disabled: drop
        if statusCode == 429 && !self.config.rateLimitConfig.enabled {
            return true
        }

        let behavior = self.resolveStatusCodeBehavior(code: statusCode)
        if behavior == .retry {
            // Rate limit config handles retryable codes that carry Retry-After — don't drop
            if self.config.rateLimitConfig.enabled {
                return false
            }
            // Retryable error with backoff disabled and no rate-limit handling: drop
            if !self.config.backoffConfig.enabled {
                return true
            }
            return false
        }

        return behavior == .drop
    }

    private func handleRetryableError(
        state: RetryState,
        response: ResponseInfo,
        currentTime: TimeInterval
    ) -> RetryState {
        let existingMetadata = state.batchMetadata[response.batchFile]
        let newFailureCount = (existingMetadata?.failureCount ?? 0) + 1
        let firstFailureTime = existingMetadata?.firstFailureTime ?? currentTime
        let nextRetryTime = currentTime + self.calculateBackoffInterval(failureCount: newFailureCount)

        let newMetadata = BatchMetadata(
            failureCount: newFailureCount,
            nextRetryTime: nextRetryTime,
            firstFailureTime: firstFailureTime
        )

        var newState = state
        newState.batchMetadata[response.batchFile] = newMetadata
        return newState
    }

    private func calculateBackoffInterval(failureCount: Int) -> TimeInterval {
        let base = self.config.backoffConfig.baseBackoffInterval
        let max = TimeInterval(config.backoffConfig.maxBackoffInterval)

        let exponentialBackoff = base * pow(2.0, Double(failureCount - 1))
        let cappedBackoff = min(exponentialBackoff, max)

        let jitterAmount = cappedBackoff * (Double(config.backoffConfig.jitterPercent) / 100.0)
        let jitter = Double.random(in: 0..<jitterAmount)

        return min(cappedBackoff + jitter, max)
    }

    private func resolveStatusCodeBehavior(code: Int) -> RetryBehavior {
        if let override = config.backoffConfig.statusCodeOverrides[code] {
            return override
        }

        switch code {
        case 400..<500:
            return self.config.backoffConfig.default4xxBehavior
        case 500..<600:
            return self.config.backoffConfig.default5xxBehavior
        default:
            return self.config.backoffConfig.unknownCodeBehavior
        }
    }

    private func handleRateLimitResponse(
        state: RetryState,
        response: ResponseInfo,
        currentTime: TimeInterval
    ) -> RetryState {
        let waitUntilTime = self.calculateWaitUntilTime(response.retryAfterSeconds, currentTime: currentTime)

        var newState = state
        newState.pipelineState = .rateLimited
        newState.waitUntilTime = waitUntilTime
        newState.globalRetryCount = state.globalRetryCount + 1
        return newState
    }

    private func calculateWaitUntilTime(_ retryAfterSeconds: Int?, currentTime: TimeInterval) -> TimeInterval {
        let seconds = retryAfterSeconds?.coerceAtLeast(0) ?? self.config.rateLimitConfig.maxRetryInterval
        let clampedSeconds = min(seconds, config.rateLimitConfig.maxRetryInterval)
        return currentTime + TimeInterval(clampedSeconds)
    }
}

/// Extension for Int to match Kotlin's coerceAtLeast
extension Int {
    func coerceAtLeast(_ minValue: Int) -> Int {
        Swift.max(self, minValue)
    }
}
