import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

interface RequestSignature {
  timestamp: string;
  nonce: string;
  signature: string;
  version: string;
  userId?: string;
}

interface SecurityValidation {
  isValid: boolean;
  trustScore: number;
  errors: string[];
  warnings: string[];
  metadata: { [key: string]: any };
}

/**
 * Anti-spoofing middleware for Firebase Cloud Functions
 * Validates request authenticity and prevents malicious attacks
 */
export class AntiSpoofingMiddleware {
  private static readonly APP_SIGNATURE_KEY = 'SwapDotz_2024_Production_Key_v1';
  private static readonly MAX_REQUEST_AGE = 300000; // 5 minutes
  private static readonly RATE_LIMIT_WINDOW = 60000; // 1 minute
  private static readonly MAX_REQUESTS_PER_WINDOW = 10;
  private static readonly MIN_TRUST_SCORE = 0.7;

  // In-memory stores (in production, use Redis or Firestore)
  private static usedNonces = new Map<string, number>();
  private static rateLimitMap = new Map<string, { count: number; windowStart: number }>();
  private static suspiciousIPs = new Set<string>();

  /**
   * Validate incoming request for anti-spoofing protection
   */
  static async validateRequest(
    data: any,
    context: functions.https.CallableContext
  ): Promise<SecurityValidation> {
    const result: SecurityValidation = {
      isValid: true,
      trustScore: 1.0,
      errors: [],
      warnings: [],
      metadata: {},
    };

    try {
      // Extract security headers
      const headers = context.rawRequest?.headers || {};
      const clientIP = this.getClientIP(context);

      // 1. Validate request signature
      const signatureValidation = this.validateRequestSignature(data, headers);
      if (!signatureValidation.isValid) {
        result.isValid = false;
        result.errors.push(...signatureValidation.errors);
        result.trustScore -= 0.3;
      }

      // 2. Check for replay attacks
      const replayValidation = this.validateReplayProtection(headers);
      if (!replayValidation.isValid) {
        result.isValid = false;
        result.errors.push(...replayValidation.errors);
        result.trustScore -= 0.4;
      }

      // 3. Rate limiting validation
      const rateLimitValidation = this.validateRateLimit(clientIP, context.auth?.uid);
      if (!rateLimitValidation.isValid) {
        result.isValid = false;
        result.errors.push(...rateLimitValidation.errors);
        result.trustScore -= 0.2;
      }

      // 4. Device fingerprint validation
      const fingerprint = Array.isArray(headers['x-swapdotz-device-fingerprint']) 
        ? headers['x-swapdotz-device-fingerprint'][0] 
        : headers['x-swapdotz-device-fingerprint'];
      const deviceValidation = await this.validateDeviceFingerprint(
        fingerprint,
        context.auth?.uid
      );
      result.trustScore *= deviceValidation.trustScore;
      result.warnings.push(...deviceValidation.warnings);

      // 5. Behavioral analysis
      const behaviorValidation = await this.validateBehaviorPattern(
        context.auth?.uid,
        data,
        context
      );
      result.trustScore *= behaviorValidation.trustScore;
      result.warnings.push(...behaviorValidation.warnings);

      // 6. IP reputation check
      const ipValidation = this.validateIPReputation(clientIP);
      if (!ipValidation.isValid) {
        result.trustScore -= 0.3;
        result.warnings.push(...ipValidation.warnings);
      }

      // Final trust score validation
      if (result.trustScore < this.MIN_TRUST_SCORE) {
        result.isValid = false;
        result.errors.push(`Trust score ${result.trustScore.toFixed(2)} below minimum ${this.MIN_TRUST_SCORE}`);
      }

      // Log security events
      await this.logSecurityEvent(result, context, clientIP);

      // Update suspicious IP tracking
      if (!result.isValid || result.trustScore < 0.5) {
        this.suspiciousIPs.add(clientIP);

        // Auto-block IPs with multiple violations
        await this.updateIPReputation(clientIP, result.trustScore);
      }

      const deviceFp = Array.isArray(headers['x-swapdotz-device-fingerprint']) 
        ? headers['x-swapdotz-device-fingerprint'][0] 
        : headers['x-swapdotz-device-fingerprint'];
      result.metadata = {
        clientIP,
        trustScore: result.trustScore,
        timestamp: Date.now(),
        userAgent: headers['user-agent'],
        deviceFingerprint: deviceFp?.substring(0, 16),
      };
    } catch (error) {
      console.error('Anti-spoofing validation error:', error);
      result.isValid = false;
      result.errors.push('Security validation failed');
      result.trustScore = 0;
    }

    return result;
  }

  /**
   * Validate request signature to prevent tampering
   */
  private static validateRequestSignature(
    data: any,
    headers: { [key: string]: any }
  ): { isValid: boolean; errors: string[] } {
    const errors: string[] = [];

    try {
      const timestamp = headers['x-swapdotz-timestamp'];
      const nonce = headers['x-swapdotz-nonce'];
      const signature = headers['x-swapdotz-signature'];
      const version = headers['x-swapdotz-version'];
      const userId = headers['x-swapdotz-user'];

      // Check required headers
      if (!timestamp || !nonce || !signature || !version) {
        errors.push('Missing required security headers');
        return { isValid: false, errors };
      }

      // Validate timestamp
      const requestTime = parseInt(timestamp);
      const currentTime = Date.now();
      const timeDiff = Math.abs(currentTime - requestTime);

      if (timeDiff > this.MAX_REQUEST_AGE) {
        errors.push(`Request timestamp outside acceptable range: ${timeDiff}ms`);
        return { isValid: false, errors };
      }

      // Validate signature
      const method = 'POST'; // Assuming HTTPS callable functions
      const path = '/functions'; // Generic path for Cloud Functions
      const body = JSON.stringify(data);
      const signaturePayload = `${method}|${path}|${body}|${timestamp}|${nonce}|${userId || 'anonymous'}`;

      const expectedSignature = this.createHMAC(signaturePayload, this.APP_SIGNATURE_KEY);

      if (signature !== expectedSignature) {
        errors.push('Request signature validation failed');
        return { isValid: false, errors };
      }

      return { isValid: true, errors: [] };
    } catch (error) {
      errors.push(`Signature validation error: ${error}`);
      return { isValid: false, errors };
    }
  }

  /**
   * Validate replay protection using nonces and timestamps
   */
  private static validateReplayProtection(
    headers: { [key: string]: any }
  ): { isValid: boolean; errors: string[] } {
    const errors: string[] = [];

    try {
      const nonce = headers['x-swapdotz-nonce'];
      const timestamp = parseInt(headers['x-swapdotz-timestamp']);

      if (!nonce) {
        errors.push('Missing nonce for replay protection');
        return { isValid: false, errors };
      }

      // Check if nonce was already used
      const lastUsed = this.usedNonces.get(nonce);
      if (lastUsed) {
        errors.push('Nonce reuse detected - potential replay attack');
        return { isValid: false, errors };
      }

      // Store nonce with timestamp
      this.usedNonces.set(nonce, timestamp);

      // Cleanup old nonces to prevent memory bloat
      this.cleanupOldNonces();

      return { isValid: true, errors: [] };
    } catch (error) {
      errors.push(`Replay protection error: ${error}`);
      return { isValid: false, errors };
    }
  }

  /**
   * Validate rate limiting to prevent abuse
   */
  private static validateRateLimit(
    clientIP: string,
    userId?: string
  ): { isValid: boolean; errors: string[] } {
    const errors: string[] = [];
    const key = userId || clientIP;
    const currentTime = Date.now();

    try {
      const rateData = this.rateLimitMap.get(key);

      if (!rateData) {
        // First request from this key
        this.rateLimitMap.set(key, {
          count: 1,
          windowStart: currentTime,
        });
        return { isValid: true, errors: [] };
      }

      // Check if we're in a new window
      if (currentTime - rateData.windowStart > this.RATE_LIMIT_WINDOW) {
        // Reset window
        this.rateLimitMap.set(key, {
          count: 1,
          windowStart: currentTime,
        });
        return { isValid: true, errors: [] };
      }

      // Increment count in current window
      rateData.count++;

      if (rateData.count > this.MAX_REQUESTS_PER_WINDOW) {
        errors.push(`Rate limit exceeded: ${rateData.count} requests in window`);
        return { isValid: false, errors };
      }

      return { isValid: true, errors: [] };
    } catch (error) {
      errors.push(`Rate limiting error: ${error}`);
      return { isValid: false, errors };
    }
  }

  /**
   * Validate device fingerprint consistency
   */
  private static async validateDeviceFingerprint(
    fingerprint?: string,
    userId?: string
  ): Promise<{ trustScore: number; warnings: string[] }> {
    const warnings: string[] = [];
    let trustScore = 1.0;

    try {
      if (!fingerprint) {
        warnings.push('Missing device fingerprint');
        return { trustScore: 0.8, warnings };
      }

      if (!userId) {
        // Anonymous user - can't validate fingerprint consistency
        return { trustScore: 0.9, warnings };
      }

      // Check fingerprint consistency in Firestore
      const db = admin.firestore();
      const userDoc = await db.collection('user_security').doc(userId).get();

      if (userDoc.exists) {
        const userData = userDoc.data();
        const knownFingerprints = userData?.device_fingerprints || [];

        if (!knownFingerprints.includes(fingerprint)) {
          // New device for this user
          if (knownFingerprints.length > 0) {
            warnings.push('New device detected for user');
            trustScore -= 0.2;
          }

          // Add new fingerprint
          await userDoc.ref.update({
            device_fingerprints: admin.firestore.FieldValue.arrayUnion(fingerprint),
            last_fingerprint_update: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      } else {
        // First time seeing this user - create security record
        await db.collection('user_security').doc(userId).set({
          device_fingerprints: [fingerprint],
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          last_fingerprint_update: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return { trustScore, warnings };
    } catch (error) {
      warnings.push(`Device fingerprint validation error: ${error}`);
      return { trustScore: 0.7, warnings };
    }
  }

  /**
   * Validate user behavior patterns
   */
  private static async validateBehaviorPattern(
    userId?: string,
    data?: any,
    context?: functions.https.CallableContext
  ): Promise<{ trustScore: number; warnings: string[] }> {
    const warnings: string[] = [];
    let trustScore = 1.0;

    try {
      if (!userId) {
        return { trustScore: 0.9, warnings }; // Anonymous users get lower baseline
      }

      const db = admin.firestore();
      const behaviorDoc = await db.collection('user_behavior').doc(userId).get();

      if (behaviorDoc.exists) {
        const behaviorData = behaviorDoc.data();
        const lastActivity = behaviorData?.last_activity;
        const currentTime = Date.now();

        // Check for suspicious rapid-fire requests
        if (lastActivity && (currentTime - lastActivity) < 1000) {
          warnings.push('Rapid successive requests detected');
          trustScore -= 0.1;
        }

        // Check for unusual request patterns
        const requestCounts = behaviorData?.request_counts || {};
        const functionName = context?.rawRequest?.url?.split('/').pop();

        if (functionName) {
          const currentCount = requestCounts[functionName] || 0;
          const values = Object.values(requestCounts) as number[];
          const avgCount = values.reduce((a: number, b: number) => a + b, 0) /
                          Object.keys(requestCounts).length || 1;

          if (currentCount > avgCount * 5) {
            warnings.push(`Unusual high frequency for function: ${functionName}`);
            trustScore -= 0.15;
          }

          // Update behavior data
          await behaviorDoc.ref.update({
            last_activity: currentTime,
            [`request_counts.${functionName}`]: admin.firestore.FieldValue.increment(1),
          });
        }
      } else {
        // Create initial behavior record
        await db.collection('user_behavior').doc(userId).set({
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          last_activity: Date.now(),
          request_counts: {},
        });
      }

      return { trustScore, warnings };
    } catch (error) {
      warnings.push(`Behavior validation error: ${error}`);
      return { trustScore: 0.8, warnings };
    }
  }

  /**
   * Validate IP reputation
   */
  private static validateIPReputation(
    clientIP: string
  ): { isValid: boolean; warnings: string[] } {
    const warnings: string[] = [];

    // Check if IP is in suspicious list
    if (this.suspiciousIPs.has(clientIP)) {
      warnings.push('Request from suspicious IP address');
      return { isValid: false, warnings };
    }

    // Additional IP reputation checks could be added here
    // (e.g., checking against external threat intelligence feeds)

    return { isValid: true, warnings: [] };
  }

  /**
   * Update IP reputation based on behavior
   */
  private static async updateIPReputation(clientIP: string, trustScore: number): Promise<void> {
    try {
      const db = admin.firestore();
      const ipDoc = db.collection('ip_reputation').doc(clientIP);

      await ipDoc.set({
        trust_score: trustScore,
        last_violation: admin.firestore.FieldValue.serverTimestamp(),
        violation_count: admin.firestore.FieldValue.increment(1),
      }, { merge: true });
    } catch (error) {
      console.error('Failed to update IP reputation:', error);
    }
  }

  /**
   * Log security events for monitoring
   */
  private static async logSecurityEvent(
    validation: SecurityValidation,
    context: functions.https.CallableContext,
    clientIP: string
  ): Promise<void> {
    try {
      const db = admin.firestore();

      if (!validation.isValid || validation.trustScore < 0.8) {
        await db.collection('security_events').add({
          event_type: validation.isValid ? 'low_trust_score' : 'validation_failed',
          client_ip: clientIP,
          user_id: context.auth?.uid || 'anonymous',
          trust_score: validation.trustScore,
          errors: validation.errors,
          warnings: validation.warnings,
          metadata: validation.metadata,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          function_name: context.rawRequest?.url?.split('/').pop(),
        });
      }
    } catch (error) {
      console.error('Failed to log security event:', error);
    }
  }

  /**
   * Helper: Create HMAC signature
   */
  private static createHMAC(data: string, key: string): string {
    const hmac = crypto.createHmac('sha256', key);
    hmac.update(data);
    return hmac.digest('base64');
  }

  /**
   * Helper: Get client IP address
   */
  private static getClientIP(context: functions.https.CallableContext): string {
    const headers = context.rawRequest?.headers || {};
    const forwardedFor = Array.isArray(headers['x-forwarded-for']) 
      ? headers['x-forwarded-for'][0] 
      : headers['x-forwarded-for'];
    const realIp = Array.isArray(headers['x-real-ip']) 
      ? headers['x-real-ip'][0] 
      : headers['x-real-ip'];
    return (
      forwardedFor?.split(',')[0] ||
      realIp ||
      context.rawRequest?.connection?.remoteAddress ||
      'unknown'
    );
  }

  /**
   * Helper: Clean up old nonces to prevent memory bloat
   */
  private static cleanupOldNonces(): void {
    const cutoffTime = Date.now() - (this.MAX_REQUEST_AGE * 2);

    for (const [nonce, timestamp] of this.usedNonces.entries()) {
      if (timestamp < cutoffTime) {
        this.usedNonces.delete(nonce);
      }
    }

    // Also cleanup rate limit data
    for (const [key, data] of this.rateLimitMap.entries()) {
      if (Date.now() - data.windowStart > this.RATE_LIMIT_WINDOW * 2) {
        this.rateLimitMap.delete(key);
      }
    }
  }

  /**
   * Create middleware wrapper for Cloud Functions
   */
  static middleware() {
    return async (data: any, context: functions.https.CallableContext) => {
      const validation = await this.validateRequest(data, context);

      if (!validation.isValid) {
        console.error('🚨 SECURITY: Request validation failed', {
          errors: validation.errors,
          trustScore: validation.trustScore,
          clientIP: this.getClientIP(context),
          userId: context.auth?.uid,
        });

        throw new functions.https.HttpsError(
          'permission-denied',
          'Security validation failed',
          {
            errors: validation.errors,
            trustScore: validation.trustScore,
          }
        );
      }

      if (validation.warnings.length > 0) {
        console.warn('⚠️ SECURITY: Request validation warnings', {
          warnings: validation.warnings,
          trustScore: validation.trustScore,
        });
      }

      return validation;
    };
  }
}
