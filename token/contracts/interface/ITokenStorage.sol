pragma solidity ^0.6.0;

import "@c-layer/oracle/contracts/interface/IUserRegistry.sol";
import "@c-layer/oracle/contracts/interface/IRatesProvider.sol";
import "./IRule.sol";


/**
 * @title ITokenStorage
 * @dev Token storage interface
 *
 * @author Cyril Lapinte - <cyril.lapinte@openfiz.com>
 * SPDX-License-Identifier: MIT
 */
abstract contract ITokenStorage {
  enum TransferCode {
    UNKNOWN,
    OK,
    INVALID_SENDER,
    NO_RECIPIENT,
    INSUFFICIENT_TOKENS,
    LOCKED,
    FROZEN,
    RULE,
    INVALID_RATE,
    NON_REGISTRED_SENDER,
    NON_REGISTRED_RECEIVER,
    LIMITED_EMISSION,
    LIMITED_RECEPTION
  }

  enum Scope {
    DEFAULT
  }

  enum AuditConfigurationCode {
    PROOF_OF_OWNERSHIP,
    LIMITABLE_TRANSFERABILITY
  }

  enum AuditStorageMode {
    ADDRESS,
    USER_ID,
    SHARED
  }

  enum AuditMode {
    NEVER,
    ALWAYS,
    ALWAYS_TRIGGERS_EXCLUDED,
    ALWAYS_TRIGGERS_ONLY,
    WHEN_TRIGGERS_MATCHED,
    WHEN_TRIGGERS_UNMATCHED
  }

  event OracleDefined(
    IUserRegistry userRegistry,
    bytes32 currency);
  event TokenDelegateDefined(uint256 indexed delegateId, address delegate, uint256[] configurations);
  event TokenDelegateRemoved(uint256 indexed delegateId);
  event AuditConfigurationDefined(
    uint256 indexed configurationId,
    uint256 scopeId,
    bool scopeCore,
    AuditMode mode,
    AuditStorageMode storageMode,
    uint256[] senderKeys,
    uint256[] receiverKeys,
    IRatesProvider ratesProvider,
    bytes32 currency);
  event AuditTriggersDefined(uint256 indexed configurationId, address[] triggers, bool[] senders, bool[] receivers, bool[] tokens);
  event AuditsRemoved(address scope, uint256 scopeId);
  event SelfManaged(address indexed holder, bool active);

  event Minted(address indexed token, uint256 amount);
  event MintFinished(address indexed token);
  event Burned(address indexed token, uint256 amount);
  event ProofCreated(address indexed token, address indexed holder, uint256 proofId);
  event RulesDefined(address indexed token, IRule[] rules);
  event LockDefined(
    address indexed token,
    uint256 startAt,
    uint256 endAt,
    address[] exceptions
  );
  event Seize(address indexed token, address account, uint256 amount);
  event Freeze(address address_, uint256 until);
  event ClaimDefined(
    address indexed token,
    address indexed claim,
    uint256 claimAt);
  event TokenDefined(
    address indexed token,
    uint256 delegateId,
    string name,
    string symbol,
    uint256 decimals);
  event TokenMigrated(address indexed token, address newCore);
  event TokenRemoved(address indexed token);
  event TransferAuditLog(
    uint256 senderId,
    uint256 receiverId,
    uint256 cumulatedEmission,
    uint256 senderLimit,
    uint256 cumulatedReception,
    uint256 receiverLimit);
}