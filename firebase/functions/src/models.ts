/**
 * TypeScript models for SwapDotz Firestore schema
 */

import { Timestamp } from 'firebase-admin/firestore';

/**
 * Represents an NFC token in the system
 */
export interface Token {
  // The unique identifier of the NFC token (e.g., 7-byte UID)
  uid: string;

  // Current owner's Firebase Auth UID
  current_owner_id: string;

  // Array of previous owner IDs for provenance tracking
  previous_owners: string[];

  // Hash or encrypted representation of the current AES key
  // Never store the actual key - this could be a salted hash or encrypted value
  key_hash: string;

  // When the token was first registered in the system
  created_at: Timestamp;

  // When the token was last transferred
  last_transfer_at: Timestamp;

  // Token metadata
  metadata: TokenMetadata;
}

/**
 * Metadata associated with a token
 */
export interface TokenMetadata {
  // Travel statistics
  travel_stats: {
    countries_visited: string[];
    cities_visited: string[];
    total_distance_km: number;
    last_location?: {
      lat: number;
      lng: number;
      timestamp: Timestamp;
    };
  };

  // Gamification/leaderboard points
  leaderboard_points: number;

  // Custom attributes that can be added
  custom_attributes?: Record<string, any>;

  // Token type/series information
  series?: string;
  edition?: string;
  rarity?: 'common' | 'uncommon' | 'rare' | 'legendary';
}

/**
 * Represents a transfer session between two users
 */
export interface TransferSession {
  // Unique session identifier
  session_id: string;

  // The token being transferred
  token_uid: string;

  // Firebase Auth UID of the current owner initiating the transfer
  from_user_id: string;

  // Firebase Auth UID of the intended recipient (optional - can be claimed by any user if not set)
  to_user_id?: string;

  // Session expiration timestamp (e.g., 5 minutes from creation)
  expires_at: Timestamp;

  // Optional nonce for additional security
  session_nonce?: string;

  // Session status
  status: 'pending' | 'completed' | 'expired' | 'cancelled';

  // When the session was created
  created_at: Timestamp;

  // Challenge data for cryptographic verification
  challenge_data?: {
    challenge: string;
    expected_response_hash?: string;
    expected_response_proof?: string;
    used?: boolean;
  };
}

/**
 * User profile data (extends Firebase Auth)
 */
export interface UserProfile {
  // Firebase Auth UID
  uid: string;

  // Display name
  display_name?: string;

  // Avatar URL
  avatar_url?: string;

  // Statistics
  stats: {
    tokens_owned: number;
    tokens_transferred_out: number;
    tokens_received: number;
    total_leaderboard_points: number;
  };

  // When the user joined
  created_at: Timestamp;

  // Last activity
  last_active_at: Timestamp;
}

/**
 * Transfer history log entry
 */
export interface TransferLog {
  // Unique log entry ID
  id: string;

  // Token that was transferred
  token_uid: string;

  // Transfer participants
  from_user_id: string;
  to_user_id: string;

  // Associated session ID
  session_id: string;

  // When the transfer completed
  completed_at: Timestamp;

  // Transfer metadata
  metadata?: {
    location?: {
      lat: number;
      lng: number;
    };
    device_info?: string;
  };
}

/**
 * Request/Response types for Cloud Functions
 */

export interface InitiateTransferRequest {
  token_uid: string;
  to_user_id?: string; // Optional - if not provided, anyone can claim
  session_duration_minutes?: number; // Default: 5 minutes
}

export interface InitiateTransferResponse {
  session_id: string;
  expires_at: string; // ISO timestamp
  challenge?: string; // Optional challenge for the recipient
}

export interface CompleteTransferRequest {
  session_id: string;
  challenge_response?: string; // Response to cryptographic challenge
  new_key_hash: string; // Hash of the new key after rekey operation
}

export interface CompleteTransferResponse {
  success: boolean;
  new_owner_id: string;
  transfer_log_id: string;
}

export interface ValidateChallengeRequest {
  session_id: string;
  challenge_response: string;
}

export interface ValidateChallengeResponse {
  valid: boolean;
  session_id: string;
}

/**
 * Staged transfer for two-phase commit rollback support
 */
export interface StagedTransfer {
  id: string;
  session_id: string;
  token_uid: string;
  from_user_id: string;
  to_user_id: string;
  
  // Original token state for rollback
  original_token_state: {
    current_owner_id: string;
    previous_owners: string[];
    key_hash: string;
  };
  
  // New token state to be applied
  new_token_state: {
    current_owner_id: string;
    previous_owners: string[];
    key_hash: string;
    last_transfer_at: Timestamp;
  };
  
  status: 'staged' | 'committed' | 'rolled_back' | 'expired';
  created_at: Timestamp;
  expires_at: Timestamp;
  committed_at?: Timestamp;
  rolled_back_at?: Timestamp;
  rollback_reason?: string;
}

/**
 * Request/Response types for new rollback-enabled functions
 */
export interface StageTransferResponse {
  success: boolean;
  staged_transfer_id: string;
  new_owner_id: string;
}

export interface CommitTransferRequest {
  staged_transfer_id: string;
}

export interface RollbackTransferRequest {
  staged_transfer_id: string;
  reason?: string;
}

export interface RollbackTransferResponse {
  success: boolean;
  message: string;
}
