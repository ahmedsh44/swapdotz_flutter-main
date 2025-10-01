/**
 * Shared type definitions for server-authoritative DESFire system
 */

// Session states
export type SessionState = 'pending' | 'complete' | 'failed';
export type SessionPhase = 'auth' | 'auth-ok' | 'mid-ok';

// Key targets
export type KeyTarget = 'mid' | 'new';

// Firebase Functions request/response types

export interface BeginAuthenticateRequest {
  tokenId: string;
  userId: string;
}

export interface BeginAuthenticateResponse {
  sessionId: string;
  apdus: string[];
  expect?: string;
}

export interface ContinueAuthenticateRequest {
  sessionId: string;
  response: string;
  idempotencyKey?: string;
}

export interface ContinueAuthenticateResponse {
  apdus?: string[];
  done: boolean;
}

export interface ChangeKeyRequest {
  sessionId: string;
  targetKey: KeyTarget;
}

export interface ChangeKeyResponse {
  apdus: string[];
  verifyToken: string;
}

export interface ConfirmChangeKeyRequest {
  sessionId: string;
  responses: string[];
  verifyToken: string;
  idempotencyKey?: string;
}

export interface ConfirmChangeKeyResponse {
  ok: boolean;
}

export interface FinalizeTransferRequest {
  sessionId: string;
  newOwnerId: string;
}

export interface FinalizeTransferResponse {
  success: boolean;
}

// APDU Service request/response types

export interface ApduAuthBeginRequest {
  sessionId: string;
  keyVersion: number;
  keyNo?: number;
}

export interface ApduAuthBeginResponse {
  apdus: string[];
  expect: string;
}

export interface ApduAuthStepRequest {
  sessionId: string;
  response: string;
  keyVersion: number;
}

export interface ApduAuthStepResponse {
  apdus?: string[];
  done: boolean;
}

export interface ApduChangeKeyRequest {
  sessionId: string;
  keyVersion: number;
  targetKey: KeyTarget;
}

export interface ApduChangeKeyResponse {
  apdus: string[];
  verifyToken: string;
}

export interface ApduChangeKeyVerifyRequest {
  sessionId: string;
  responses: string[];
  verifyToken: string;
  keyVersion: number;
}

export interface ApduChangeKeyVerifyResponse {
  ok: boolean;
  error?: string;
}

// Firestore document types

export interface TokenDocument {
  ownerId: string;
  keyVersion: number;
  lock?: {
    leaseId: string;
    expiresAt: FirebaseFirestore.Timestamp;
  };
  previousOwners?: string[];
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface SessionDocument {
  tokenId: string;
  state: SessionState;
  phase: SessionPhase;
  keyVersion: number;
  expiresAt: FirebaseFirestore.Timestamp;
  createdAt: FirebaseFirestore.Timestamp;
  leaseId?: string;
  idempotencyKeys?: {
    [key: string]: boolean;
  };
  userId?: string;
}

export interface AuditLogEntry {
  type: 'transfer' | 'key_change' | 'auth_failure';
  sessionId: string;
  timestamp: FirebaseFirestore.Timestamp;
  previousOwner?: string;
  newOwner?: string;
  keyVersion?: number;
  details?: Record<string, any>;
}

// Error codes
export enum ErrorCode {
  SESSION_EXPIRED = 'SESSION_EXPIRED',
  TOKEN_LOCKED = 'TOKEN_LOCKED',
  AUTH_FAILED = 'AUTH_FAILED',
  KEY_CHANGE_FAILED = 'KEY_CHANGE_FAILED',
  INVALID_PHASE = 'INVALID_PHASE',
  INVALID_STATE = 'INVALID_STATE',
  TOKEN_NOT_FOUND = 'TOKEN_NOT_FOUND',
  SESSION_NOT_FOUND = 'SESSION_NOT_FOUND',
  UNAUTHORIZED = 'UNAUTHORIZED',
  INVALID_REQUEST = 'INVALID_REQUEST'
}

// DESFire constants
export const DESFIRE_COMMANDS = {
  AUTHENTICATE_ISO: 0x1A,
  AUTHENTICATE_AES: 0xAA,
  AUTHENTICATE_LEGACY: 0x0A,
  ADDITIONAL_FRAME: 0xAF,
  CHANGE_KEY: 0xC4,
  GET_KEY_SETTINGS: 0x45,
  CHANGE_KEY_SETTINGS: 0x54,
  CREATE_APPLICATION: 0xCA,
  DELETE_APPLICATION: 0xDA,
  SELECT_APPLICATION: 0x5A,
  CREATE_FILE: 0xCD,
  DELETE_FILE: 0xDF,
  READ_DATA: 0xBD,
  WRITE_DATA: 0x3D,
  GET_FILE_IDS: 0x6F,
  GET_FILE_SETTINGS: 0xF5
} as const;

export const DESFIRE_STATUS_CODES = {
  SUCCESS: '9100',
  ADDITIONAL_FRAME: '91AF',
  LENGTH_ERROR: '917E',
  AUTH_ERROR: '91AE',
  CRYPTO_ERROR: '9197',
  PERMISSION_DENIED: '919D',
  PARAMETER_ERROR: '919E',
  APPLICATION_NOT_FOUND: '91A0',
  FILE_NOT_FOUND: '91F0',
  OUT_OF_MEMORY: '910E',
  COMMAND_ABORTED: '91CA'
} as const; 