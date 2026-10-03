--!strict
-- Token-bucket rate limiter keyed by an arbitrary key (usually the player).
-- The clock is injected so the limiter is pure and testable.

export type RateLimiter = {
	capacity: number,
	refillPerSecond: number,
	buckets: { [any]: { tokens: number, updated: number } },
	check: (self: RateLimiter, key: any, now: number) -> boolean,
	forget: (self: RateLimiter, key: any) -> (),
}

local RateLimiter = {}

local function check(self: RateLimiter, key: any, now: number): boolean
	local bucket = self.buckets[key]
	if bucket == nil then
		bucket = { tokens = self.capacity, updated = now }
		self.buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.updated)
	bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refillPerSecond)
	bucket.updated = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

local function forget(self: RateLimiter, key: any)
	self.buckets[key] = nil
end

-- `perSecond` sustained calls, bursts up to `burst`.
function RateLimiter.new(perSecond: number, burst: number): RateLimiter
	return {
		capacity = burst,
		refillPerSecond = perSecond,
		buckets = {},
		check = check,
		forget = forget,
	}
end

return RateLimiter
