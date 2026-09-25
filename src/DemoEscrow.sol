// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Sandbox escrow that reproduces the control gap the platform guards:
/// release authority is only `msg.sender == escrow.oracle`. The contract knows
/// nothing about application approval.
///
/// Legacy and guarded modes use this same contract. The difference is the
/// per-escrow oracle chosen at creation: an EOA (legacy) or GuardExecutor
/// (guarded). Terms are immutable after creation, and release is one-shot
/// (Funded -> Released), so a single escrow can never pay out twice.
///
/// Emergency brake: a guardian (or the admin) can pause all releases and
/// refunds, or a single escrow. Only the admin can lift a pause, so a
/// compromised or over-eager guardian can stop funds from moving but can never
/// move them.
contract DemoEscrow {
    enum State {
        None,
        Created,
        Funded,
        Released,
        Refunded,
        Cancelled
    }

    struct Escrow {
        address buyer;
        address seller;
        address token;
        uint256 amount;
        bytes32 titleId;
        address oracle;
        State state;
    }

    address public immutable admin;
    /// Account allowed to pause (never to unpause). Defaults to the deployer.
    address public guardian;
    /// Global pause: blocks every release and refund.
    bool public paused;
    uint256 public nextEscrowId = 1;
    mapping(uint256 => Escrow) private _escrows;
    /// Per-escrow pause: blocks release and refund of that escrow only.
    mapping(uint256 => bool) public escrowPaused;
    mapping(bytes32 => uint256[]) private _escrowsByTitle;
    /// When the buyer asked for a refund (block timestamp), 0 if never.
    mapping(uint256 => uint256) public refundRequestedAt;

    /// `titleId` is the vehicle / order id; it is indexed so every escrow of one
    /// title can be found from logs (see also `escrowIdsByTitle`).
    event EscrowCreated(
        uint256 indexed escrowId,
        bytes32 indexed titleId,
        address indexed buyer,
        address seller,
        address token,
        uint256 amount,
        address oracle
    );
    event EscrowFunded(uint256 indexed escrowId, address indexed buyer, uint256 amount);
    event EscrowReleased(
        uint256 indexed escrowId, address indexed seller, address token, uint256 amount, address indexed caller
    );
    event EscrowRefunded(uint256 indexed escrowId, address indexed buyer, uint256 amount);
    event EscrowCancelled(uint256 indexed escrowId);
    event RefundRequested(uint256 indexed escrowId, bytes32 indexed titleId, address indexed buyer, string reason);
    event GuardianSet(address indexed previousGuardian, address indexed newGuardian);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event EscrowPaused(uint256 indexed escrowId, address indexed account);
    event EscrowUnpaused(uint256 indexed escrowId, address indexed account);

    error NotAdmin();
    error NotBuyer();
    error NotOracle();
    error NotGuardian();
    error ZeroAddress();
    error UnknownEscrow(uint256 escrowId);
    error ContractPaused();
    error EscrowIsPaused(uint256 escrowId);
    error RefundAlreadyRequested(uint256 escrowId);
    error InvalidTerms();
    error InvalidState(State expected, State actual);
    error TokenTransferFailed();

    constructor() {
        admin = msg.sender;
        guardian = msg.sender;
        emit GuardianSet(address(0), msg.sender);
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyGuardianOrAdmin() {
        if (msg.sender != guardian && msg.sender != admin) revert NotGuardian();
        _;
    }

    /// Blocks money-moving calls while the contract or this escrow is paused.
    modifier whenNotPaused(uint256 escrowId) {
        if (paused) revert ContractPaused();
        if (escrowPaused[escrowId]) revert EscrowIsPaused(escrowId);
        _;
    }

    function createEscrow(
        address buyer,
        address seller,
        address token,
        uint256 amount,
        bytes32 titleId,
        address oracle
    ) external onlyAdmin returns (uint256 escrowId) {
        if (buyer == address(0) || seller == address(0) || token == address(0) || oracle == address(0) || amount == 0)
        {
            revert InvalidTerms();
        }
        escrowId = nextEscrowId++;
        _escrows[escrowId] = Escrow(buyer, seller, token, amount, titleId, oracle, State.Created);
        _escrowsByTitle[titleId].push(escrowId);
        emit EscrowCreated(escrowId, titleId, buyer, seller, token, amount, oracle);
    }

    function fund(uint256 escrowId) external {
        Escrow storage e = _escrows[escrowId];
        _requireState(e, State.Created);
        if (msg.sender != e.buyer) revert NotBuyer();
        e.state = State.Funded;
        _safeTransferFrom(e.token, e.buyer, address(this), e.amount);
        emit EscrowFunded(escrowId, e.buyer, e.amount);
    }

    /// @notice The protected effect. Pays the saved seller the saved amount.
    function release(uint256 escrowId) external whenNotPaused(escrowId) {
        Escrow storage e = _escrows[escrowId];
        if (msg.sender != e.oracle) revert NotOracle();
        _requireState(e, State.Funded);
        e.state = State.Released;
        _safeTransfer(e.token, e.seller, e.amount);
        emit EscrowReleased(escrowId, e.seller, e.token, e.amount, msg.sender);
    }

    /// Buyer flags a funded escrow as disputed ("please refund, the car failed
    /// inspection"). Demo design: this only records the request and emits an
    /// event. It deliberately does NOT block `release`, so the conflict between
    /// a pending refund request and a release is left to the off-chain policy
    /// that authorizes guarded releases. A production escrow would likely
    /// enforce it on-chain as well.
    function requestRefund(uint256 escrowId, string calldata reason) external {
        Escrow storage e = _escrows[escrowId];
        _requireState(e, State.Funded);
        if (msg.sender != e.buyer) revert NotBuyer();
        if (refundRequestedAt[escrowId] != 0) revert RefundAlreadyRequested(escrowId);
        refundRequestedAt[escrowId] = block.timestamp;
        emit RefundRequested(escrowId, e.titleId, msg.sender, reason);
    }

    function refund(uint256 escrowId) external onlyAdmin whenNotPaused(escrowId) {
        Escrow storage e = _escrows[escrowId];
        _requireState(e, State.Funded);
        e.state = State.Refunded;
        _safeTransfer(e.token, e.buyer, e.amount);
        emit EscrowRefunded(escrowId, e.buyer, e.amount);
    }

    function cancel(uint256 escrowId) external onlyAdmin {
        Escrow storage e = _escrows[escrowId];
        _requireState(e, State.Created);
        e.state = State.Cancelled;
        emit EscrowCancelled(escrowId);
    }

    /* ------------------------------------------------------------------ */
    /* Emergency controls                                                   */
    /* ------------------------------------------------------------------ */

    function setGuardian(address newGuardian) external onlyAdmin {
        if (newGuardian == address(0)) revert ZeroAddress();
        emit GuardianSet(guardian, newGuardian);
        guardian = newGuardian;
    }

    /// Stops every release and refund until the admin unpauses.
    function pause() external onlyGuardianOrAdmin {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// Stops release and refund of one escrow until the admin unpauses it.
    function pauseEscrow(uint256 escrowId) external onlyGuardianOrAdmin {
        if (_escrows[escrowId].state == State.None) revert UnknownEscrow(escrowId);
        escrowPaused[escrowId] = true;
        emit EscrowPaused(escrowId, msg.sender);
    }

    function unpauseEscrow(uint256 escrowId) external onlyAdmin {
        escrowPaused[escrowId] = false;
        emit EscrowUnpaused(escrowId, msg.sender);
    }

    /* ------------------------------------------------------------------ */
    /* Views                                                                */
    /* ------------------------------------------------------------------ */

    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return _escrows[escrowId];
    }

    function isRefundRequested(uint256 escrowId) external view returns (bool) {
        return refundRequestedAt[escrowId] != 0;
    }

    /// Every escrow created for `titleId`, oldest first, whatever its state.
    function escrowIdsByTitle(bytes32 titleId) external view returns (uint256[] memory) {
        return _escrowsByTitle[titleId];
    }

    function _requireState(Escrow storage e, State expected) private view {
        if (e.state != expected) revert InvalidState(expected, e.state);
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        _callToken(token, abi.encodeWithSignature("transfer(address,uint256)", to, value));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) private {
        _callToken(token, abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value));
    }

    function _callToken(address token, bytes memory data) private {
        // A call to an address without code succeeds silently; treat it as failure.
        if (token.code.length == 0) revert TokenTransferFailed();
        (bool ok, bytes memory ret) = token.call(data);
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TokenTransferFailed();
    }
}
