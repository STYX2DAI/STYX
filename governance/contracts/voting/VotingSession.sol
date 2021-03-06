pragma solidity ^0.6.0;

import "@c-layer/common/contracts/operable/OperableAsCore.sol";
import "../interface/IVotingSession.sol";
import "./VotingStorage.sol";


/**
 * @title VotingSession
 * @dev VotingSession contract
 * @author Cyril Lapinte - <cyril.lapinte@openfiz.com>
 * SPDX-License-Identifier: MIT
 *
 * Error messages
 *   VS02: Not the proposal author
 *   VS03: Session doesn't exist
 *   VS04: Proposal doesn't exist
 *   VS05: Inconsistent numbers of min participations
 *   VS06: Inconsistent numbers of quorums
 *   VS07: Not enought tokens for a new proposal
 *   VS08: Too many proposals yet for this session
 *   VS09: The session is not in PLANNED state
 *   VS10: The proposal is cancelled
 *   VS11: The voter has already voted
 *   VS12: Wrong votes number
 *   VS13: Session is not in VOTING state
 *   VS14: Session is not in REVEAL state
 *   VS15: Previous session is not in GRACE state anymore
 *   VS16: The resolution is already executed
 *   VS17: The resolution failed
 *   VS18: The provided salt does not match the secret hash
 *   VS19: The resolution has not been approved
 *   VS20: Default majority cannot be null
 *   VS21: Token must have a valid core
 *   VS22: Token must be successfully locked
 *   VS23: Session is not in PLANNED state
 *   VS24: Previous session resolution can be executed only in PLANNED state
 *   VS25: Proposal must be from the most recently validated session.
 *   VS26: Voting and grace period cannot be zero
 *   VS27: Session period must not overflow
 *   VS28: At least one proposal should be allowed
 *   VS29: New proposal threshold must be greater than 0
 *   VS30: Execute resolution threshold must be greater than 0
 *   VS31: Not enougth tokens to execute
 *   VS32: Inconsistent numbers of methods signatures
 */
contract VotingSession is VotingStorage, IVotingSession, OperableAsCore {

  modifier onlyProposalAuthor(uint256 _proposalId) {
    require(_proposalId < proposalsCount_, "VS04");
    require(msg.sender == proposals[_proposalId].proposedBy, "VS02");
    _;
  }

  /**
   * @dev constructor
   */
  constructor(ITokenProxy _token) public {
    token_ = _token;
    core_ = ITokenCore(token_.core());
    require(address(core_) != address(0), "VS21");
    resolutionRequirements[UNDEFINED_TARGET][ANY_METHODS] =
      ResolutionRequirement(DEFAULT_MAJORITY, DEFAULT_QUORUM);
  }

  /**
   * @dev sessionRule
   */
  function sessionRule() public override view returns (
    uint64 campaignPeriod,
    uint64 votingPeriod,
    uint64 revealPeriod,
    uint64 gracePeriod,
    uint8 maxProposals,
    uint8 maxProposalsOperator,
    uint256 newProposalThreshold,
    uint256 executeResolutionThreshold) {
    return (
      sessionRule_.campaignPeriod,
      sessionRule_.votingPeriod,
      sessionRule_.revealPeriod,
      sessionRule_.gracePeriod,
      sessionRule_.maxProposals,
      sessionRule_.maxProposalsOperator,
      sessionRule_.newProposalThreshold,
      sessionRule_.executeResolutionThreshold);
  }

  /**
   * @dev resolutionRequirement
   */
  function resolutionRequirement(address _target, bytes4 _method) public override view returns (
    uint256 majority,
    uint256 quorum) {
    ResolutionRequirement storage requirement =
      resolutionRequirements[_target][_method];

    return (
      requirement.majority,
      requirement.quorum);
  }

  /**
   * @dev sessionsCount
   */
  function sessionsCount() public override view returns (uint256) {
    return sessionsCount_;
  }

  /**
   * @dev currentSessionId
   */
  function currentSessionId() public override view returns (uint256) {
    require(sessionsCount_ > 0, "VS03");
    return sessionsCount_;
  }

  /**
   * @dev session
   */
  function session(uint256 _sessionId) public override view returns (
    uint64 startAt,
    uint256 proposalsCount,
    uint256 participation) {
    require(_sessionId > 0 && _sessionId <= sessionsCount_, "VS03");
    Session storage session_ = sessions[_sessionId];
    return (
      session_.startAt,
      session_.proposalsCount,
      session_.participation);
  }

  /**
   * @dev lastVote
   */
  function lastVote(address _voter) public override view returns (uint64 at) {
    return lastVotes[_voter];
  }

  /**
   * @dev secretHash
   */
  function secretHash(address _voter) public override view returns (bytes32) {
    return secretHashes[_voter];
  }

  /**
   * @dev token
   */
  function token() public override view returns (ITokenProxy) {
    return token_;
  }

  /**
   * @dev proposalsCount
   */
  function proposalsCount() public override view returns (uint256) {
    return proposalsCount_;
  }

  /**
   * @dev proposal
   */
  function proposal(uint256 _proposalId) public override view returns (
    uint256 sessionId,
    string memory name,
    string memory url,
    bytes32 proposalHash,
    address proposedBy,
    address resolutionTarget,
    bytes memory resolutionAction,
    uint256 weight,
    uint256 approvals,
    bool resolutionExecuted,
    bool cancelled
  ) {
    require(_proposalId < proposalsCount_, "VS04");
    Proposal storage proposal_ = proposals[_proposalId];
    return (
      proposal_.sessionId,
      proposal_.name,
      proposal_.url,
      proposal_.proposalHash,
      proposal_.proposedBy,
      proposal_.resolutionTarget,
      proposal_.resolutionAction,
      proposal_.weight,
      proposal_.approvals,
      proposal_.resolutionExecuted,
      proposal_.cancelled);
  }

  /**
   * @dev isApproved
   */
  function isApproved(uint256 _proposalId) public override view returns (bool) {
    require(_proposalId < proposalsCount_, "VS04");

    Proposal storage proposal_ = proposals[_proposalId];
    require(!proposal_.cancelled, "VS10");

    Session storage session_ = sessions[proposal_.sessionId];
    bytes4 actionSignature = readSignatureInternal(proposal_.resolutionAction);
    ResolutionRequirement storage requirement =
      resolutionRequirements[proposal_.resolutionTarget][actionSignature];

    uint256 majority = requirement.majority;
    uint256 quorum = requirement.quorum;

    if (majority == 0 && quorum == 0) {
      requirement = resolutionRequirements[proposal_.resolutionTarget][bytes4(ANY_METHODS)];
      majority = requirement.majority;
      quorum = requirement.quorum;
    }

    if (majority == 0 && quorum == 0) {
      requirement = resolutionRequirements[UNDEFINED_TARGET][actionSignature];
      majority = requirement.majority;
      quorum = requirement.quorum;
    }

    if (majority == 0 && quorum == 0) {
      requirement = resolutionRequirements[UNDEFINED_TARGET][bytes4(ANY_METHODS)];
      majority = requirement.majority;
      quorum = requirement.quorum;
    }

    uint256 totalSupply = token_.totalSupply();

    return (session_.participation != 0 && totalSupply != 0)
      && proposal_.approvals.mul(100).div(session_.participation) > majority
      && session_.participation.mul(100).div(totalSupply) > quorum;
  }

  /**
   * @dev sessionStateAt
   */
  function sessionStateAt(uint256 _sessionId, uint256 _time) public override view returns (SessionState) {
    require(_sessionId > 0 && _sessionId <= sessionsCount_, "VS03");
    Session storage session_ = sessions[_sessionId];

    uint256 startAt = uint256(session_.startAt);
    if (startAt < sessionRule_.campaignPeriod) {
      return SessionState.CLOSED;
    }

    if (_time < startAt.sub(sessionRule_.campaignPeriod)) {
      return SessionState.PLANNED;
    }

    if (_time < startAt) {
      return SessionState.CAMPAIGN;
    }

    if (_time < startAt.add(sessionRule_.votingPeriod))
    {
      return SessionState.VOTING;
    }

    if (_time < startAt.add(
      sessionRule_.votingPeriod).add(sessionRule_.revealPeriod))
    {
      return SessionState.REVEAL;
    }

    if (_time < startAt.add(
      sessionRule_.votingPeriod).add(sessionRule_.revealPeriod).add(sessionRule_.gracePeriod))
    {
      return SessionState.GRACE;
    }

    return SessionState.CLOSED;
  }

  /**
   * @dev buildHash
   */
  function buildHash(bytes memory _data) public override view returns (bytes32) {
    return keccak256(_data);
  }

  /**
   * @dev updateSessionRule
   */
  function updateSessionRule(
    uint64 _campaignPeriod,
    uint64 _votingPeriod,
    uint64 _revealPeriod,
    uint64 _gracePeriod,
    uint8 _maxProposals,
    uint8 _maxProposalsOperator,
    uint256 _newProposalThreshold,
    uint256 _executeResolutionThreshold
  )  public override onlyProxyOperator(token_) returns (bool) {
    require(_votingPeriod != 0 && _gracePeriod != 0, "VS26");
    uint256 sessionPeriod = uint256(sessionRule_.campaignPeriod)
      .add(sessionRule_.votingPeriod)
      .add(sessionRule_.revealPeriod)
      .add(sessionRule_.gracePeriod);
    require(sessionPeriod != 0, "VS27");
    require(_maxProposals != 0 || _maxProposalsOperator != 0, "VS28");
    require(_newProposalThreshold != 0, "VS29");
    require(_executeResolutionThreshold != 0, "VS30");
 
    sessionRule_ = SessionRule(
      _campaignPeriod,
      _votingPeriod,
      _revealPeriod,
      _gracePeriod,
      _maxProposals,
      _maxProposalsOperator,
      _newProposalThreshold,
      _executeResolutionThreshold);

    emit SessionRuleUpdated(
      _campaignPeriod,
      _votingPeriod,
      _revealPeriod,
      _gracePeriod,
      _maxProposals,
      _maxProposalsOperator,
      _newProposalThreshold,
      _executeResolutionThreshold);
    return true;
  }

  /**
   * @dev updateResolutionRequirements
   */
  function updateResolutionRequirements(
    address[] memory _targets,
    bytes4[] memory _methodSignatures,
    uint256[] memory _majorities,
    uint256[] memory _quorums
  ) public override onlyProxyOperator(token_) returns (bool)
  {
    require(_targets.length == _methodSignatures.length, "VS32");
    require(_methodSignatures.length == _majorities.length, "VS05");
    require(_methodSignatures.length == _quorums.length, "VS06");

    for(uint256 i=0; i < _methodSignatures.length; i++) {
      require(!(_targets[i] == UNDEFINED_TARGET && _methodSignatures[i] == ANY_METHODS) ||
        _majorities[i] != 0, "VS20");

      resolutionRequirements[_targets[i]][_methodSignatures[i]] =
        ResolutionRequirement(_majorities[i], _quorums[i]);
      emit ResolutionRequirementUpdated(
         _targets[i], _methodSignatures[i], _majorities[i], _quorums[i]);
    }
    return true;
  }

  /**
   * @dev defineProposal
   */
  function defineProposal(
    string memory _name,
    string memory _url,
    bytes32 _proposalHash,
    address _resolutionTarget,
    bytes memory _resolutionAction) public override returns (bool)
  {
    Session storage session_ = loadSessionInternal();
    uint256 balance = token_.balanceOf(msg.sender);

    if (isProxyOperator(msg.sender, token_)) {
      require(session_.proposalsCount < sessionRule_.maxProposalsOperator, "VS08");
    } else {
      require(balance >= sessionRule_.newProposalThreshold, "VS07");
      require(session_.proposalsCount < sessionRule_.maxProposals, "VS08");
    }

    uint256 proposalId = proposalsCount_++;
    Proposal storage proposal_ = proposals[proposalId];
    proposal_.sessionId = currentSessionId();
    proposal_.name = _name;
    proposal_.url = _url;
    proposal_.proposedBy = msg.sender;
    proposal_.proposalHash = _proposalHash;
    proposal_.resolutionTarget = _resolutionTarget;
    proposal_.resolutionAction = _resolutionAction;
    proposal_.weight = balance;
    
    session_.proposalsCount++;
    emit ProposalDefined(proposalId);
    return true;
  }

  /**
   * @dev updateProposal
   */
  function updateProposal(
    uint256 _proposalId,
    string memory _name,
    string memory _url,
    bytes32 _proposalHash,
    address _resolutionTarget,
    bytes memory _resolutionAction
  ) public override onlyProposalAuthor(_proposalId) returns (bool)
  {
    require(sessionStateAt(currentSessionId(), currentTime()) == SessionState.PLANNED, "VS23");

    Proposal storage proposal_ = proposals[_proposalId];
    proposal_.name = _name;
    proposal_.url = _url;
    proposal_.proposalHash = _proposalHash;
    proposal_.resolutionTarget = _resolutionTarget;
    proposal_.resolutionAction = _resolutionAction;

    emit ProposalUpdated(_proposalId);
    return true;
  }

  /**
   * @dev cancelProposal
   */
  function cancelProposal(uint256 _proposalId)
    public override onlyProposalAuthor(_proposalId) returns (bool)
  {
    require(sessionStateAt(currentSessionId(), currentTime()) == SessionState.PLANNED, "VS23");
    require(!proposals[_proposalId].cancelled, "VS10");

    proposals[_proposalId].cancelled = true;
    emit ProposalCancelled(_proposalId);
    return true;
  }

  /**
   * @dev vote
   */
  function submitVote(bool[] memory _votes) public override returns (bool)
  {
    require(sessionStateAt(currentSessionId(), currentTime()) == SessionState.VOTING, "VS13");
    return submitVoteInternal(_votes);
  }

  /**
   * @dev voteSecret
   */
  function submitVoteSecret(bytes32 _secretHash) public override returns (bool)
  {
    uint256 currentSessionId_ = currentSessionId();
    require(sessionStateAt(currentSessionId_, currentTime()) == SessionState.VOTING, "VS13");
    Session storage session_ = sessions[currentSessionId_];
    require(lastVotes[msg.sender] < session_.startAt, "VS11");

    secretHashes[msg.sender] = _secretHash;
    emit VoteSecret(currentSessionId_, msg.sender);
    return true;
  }

  /**
   * @dev reveal
   */
  function revealVoteSecret(bool[] memory _votes, bytes32 /*_salt*/) public override returns (bool)
  {
    uint256 currentSessionId_ = currentSessionId();
    require(sessionStateAt(currentSessionId_, currentTime()) == SessionState.REVEAL, "VS14");
    Session storage session_ = sessions[currentSessionId_];
    require(lastVotes[msg.sender] < session_.startAt, "VS11");
    require(buildHash(msg.data) == secretHashes[msg.sender], "VS18");

    emit VoteRevealed(currentSessionId_, msg.sender);
    return submitVoteInternal(_votes);
  }

  /**
   * @dev execute resolution
   */
  function executeResolution(uint256 _proposalId) public override returns (bool)
  {
    uint256 sessionId_ = currentSessionId();

    if (!isProxyOperator(msg.sender, token_)) {
      uint256 balance = token_.balanceOf(msg.sender);
      require(balance >= sessionRule_.executeResolutionThreshold, "VS31");
    }

    SessionState currentSessionState = sessionStateAt(sessionId_, currentTime());
    if(currentSessionState != SessionState.GRACE) {
      require(currentSessionState == SessionState.PLANNED, "VS24");
      // The next session has not started yet, previous session proposals can still be executed
      sessionId_--;
      require(sessionStateAt(sessionId_, currentTime()) == SessionState.GRACE, "VS15");
    }

    require(_proposalId < proposalsCount_, "VS04");
    Proposal storage proposal_ = proposals[_proposalId];

    require(proposal_.sessionId == sessionId_, "VS25");
    require(!proposal_.resolutionExecuted, "VS16");
    require(isApproved(_proposalId), "VS19");

    proposal_.resolutionExecuted = true;

    if (proposal_.resolutionTarget != UNDEFINED_TARGET) {
      // solhint-disable-next-line avoid-call-value, avoid-low-level-calls
      (bool success, ) = proposal_.resolutionTarget.call(proposal_.resolutionAction);
      require(success, "VS17");
    }

    emit ResolutionExecuted(_proposalId);
    return true;
  }

  /**
   * @dev execute many resolution
   */
  function executeManyResolutions(uint256[] memory _proposalIds) public override returns (bool)
  {
    for (uint256 i=0; i < _proposalIds.length; i++) {
      executeResolution(_proposalIds[i]);
    }
    return true;
  }

  /**
   * @dev read signature
   * @param _data contains the selector
   */
  function readSignatureInternal(bytes memory _data) internal pure returns (bytes4 signature) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      signature := mload(add(_data, 0x20))
    }
  }

  /**
   * @dev load session internal
   */
  function loadSessionInternal() internal returns (Session storage session_) {
    uint256 time = currentTime();

    uint256 currentSessionId_ = 0;
    SessionState state = SessionState.CLOSED;
    if (sessionsCount_ != 0) {
      currentSessionId_ = currentSessionId();
      state = sessionStateAt(currentSessionId_, time);
    }

    if(state != SessionState.PLANNED) {
      // Creation of a new session
      require(state == SessionState.GRACE || state == SessionState.CLOSED, "VS09");
      uint256 sessionPeriod = uint256(sessionRule_.campaignPeriod)
        .add(sessionRule_.votingPeriod)
        .add(sessionRule_.revealPeriod)
        .add(sessionRule_.gracePeriod);

      uint256 previousStartAt =
        (sessionsCount_ != 0) ? sessions[currentSessionId_].startAt : 0;
      uint nextAvailableSession;
      if (state == SessionState.GRACE) {
        nextAvailableSession =
          ((time.sub(previousStartAt)).div(sessionPeriod)).add(1);
      } else {
        nextAvailableSession =
          (((time.sub(previousStartAt)).add(sessionRule_.campaignPeriod)).div(sessionPeriod)).add(1);
      }

      uint256 nextStartAt = nextAvailableSession.mul(sessionPeriod).add(previousStartAt);

      session_ = sessions[++sessionsCount_];
      session_.startAt = uint64(nextStartAt);

      require(core_.defineLock(
        address(token_),
        nextStartAt,
        nextStartAt.add(sessionRule_.votingPeriod).add(sessionRule_.revealPeriod),
        new address[](0)), "VS22");

      emit SessionScheduled(sessionsCount_, session_.startAt);
    } else {
      session_ = sessions[currentSessionId_];
    }
  }

  /**
   * @dev submit vote internal
   */
  function submitVoteInternal(bool[] memory _votes) internal returns (bool)
  {
    uint256 currentSessionId_ = currentSessionId();
    Session storage session_ = sessions[currentSessionId_];
    require(lastVotes[msg.sender] < session_.startAt, "VS11");
    require(_votes.length == session_.proposalsCount, "VS12");

    uint256 weight = token_.balanceOf(msg.sender);
    for(uint256 i=0; i < session_.proposalsCount; i++) {
      if(_votes[i]) {
        uint256 proposalId = proposalsCount_ - session_.proposalsCount + i;
        Proposal storage proposal_ = proposals[proposalId];
        proposal_.approvals += (proposal_.cancelled) ? 0: weight;
      }
    }

    lastVotes[msg.sender] = uint64(currentTime());
    delete secretHashes[msg.sender];
    session_.participation += weight;

    emit Vote(currentSessionId_, msg.sender, weight);
    return true;
  }
}
