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
    uint256 public nextEscrowId = 1;
    mapping(uint256 => Escrow) private _escrows;

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        address token,
        uint256 amount,
        bytes32 titleId,
        address oracle
    );
    event EscrowFunded(uint256 indexed escrowId, address indexed buyer, uint256 amount);
    event EscrowReleased(
        uint256 indexed escrowId, address indexed seller, address token, uint256 amount, address indexed caller
    );
    event EscrowRefunded(uint256 indexed escrowId, address indexed buyer, uint256 amount);
    event EscrowCancelled(uint256 indexed escrowId);

    error NotAdmin();
    error NotBuyer();
    error NotOracle();
    error InvalidTerms();
    error InvalidState(State expected, State actual);
    error TokenTransferFailed();

    constructor() {
        admin = msg.sender;
    }

    function createEscrow(
        address buyer,
        address seller,
        address token,
        uint256 amount,
        bytes32 titleId,
        address oracle
    ) external returns (uint256 escrowId) {
        if (msg.sender != admin) revert NotAdmin();
        if (buyer == address(0) || seller == address(0) || token == address(0) || oracle == address(0) || amount == 0)
        {
            revert InvalidTerms();
        }
        escrowId = nextEscrowId++;
        _escrows[escrowId] = Escrow(buyer, seller, token, amount, titleId, oracle, State.Created);
        emit EscrowCreated(escrowId, buyer, seller, token, amount, titleId, oracle);
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
    function release(uint256 escrowId) external {
        Escrow storage e = _escrows[escrowId];
        if (msg.sender != e.oracle) revert NotOracle();
        _requireState(e, State.Funded);
        e.state = State.Released;
        _safeTransfer(e.token, e.seller, e.amount);
        emit EscrowReleased(escrowId, e.seller, e.token, e.amount, msg.sender);
    }

    function refund(uint256 escrowId) external {
        if (msg.sender != admin) revert NotAdmin();
        Escrow storage e = _escrows[escrowId];
        _requireState(e, State.Funded);
        e.state = State.Refunded;
        _safeTransfer(e.token, e.buyer, e.amount);
        emit EscrowRefunded(escrowId, e.buyer, e.amount);
    }

    function cancel(uint256 escrowId) external {
        if (msg.sender != admin) revert NotAdmin();
        Escrow storage e = _escrows[escrowId];
        _requireState(e, State.Created);
        e.state = State.Cancelled;
        emit EscrowCancelled(escrowId);
    }

    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return _escrows[escrowId];
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
