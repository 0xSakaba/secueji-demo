// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DemoEscrow} from "./DemoEscrow.sol";

/// @notice On-chain enforcement point for guarded escrows (MVP Spec 4.6).
///
/// An escrow whose oracle is this contract can only be released when:
/// - a registered human approver signed the exact ReleaseIntent (EIP-712),
/// - the platform signer issued an Authorization bound to that same intent,
/// - neither the intent nor the authorization has expired,
/// - the intent nonce has never been used,
/// - the intent matches the escrow's on-chain terms.
///
/// Anyone may submit a valid bundle; the signatures are the authority. The
/// Agent never holds either key.
contract GuardExecutor {
    /// Exact release intent the human approver signs. `businessRef` is a hash of
    /// the off-chain order / payment reference.
    struct ReleaseIntent {
        address escrow;
        uint256 escrowId;
        bytes32 titleId;
        address token;
        address beneficiary;
        uint256 amount;
        bytes32 businessRef;
        bytes32 policyVersion;
        uint256 nonce;
        uint256 expiry;
    }

    /// Short-lived platform authorization over one intent.
    struct Authorization {
        bytes32 intentHash;
        bytes32 policyVersion;
        bytes32 evidenceHash;
        uint256 nonce;
        uint256 expiry;
    }

    bytes32 public constant RELEASE_INTENT_TYPEHASH = keccak256(
        "ReleaseIntent(address escrow,uint256 escrowId,bytes32 titleId,address token,address beneficiary,uint256 amount,bytes32 businessRef,bytes32 policyVersion,uint256 nonce,uint256 expiry)"
    );
    bytes32 public constant AUTHORIZATION_TYPEHASH = keccak256(
        "Authorization(bytes32 intentHash,bytes32 policyVersion,bytes32 evidenceHash,uint256 nonce,uint256 expiry)"
    );
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("GuardExecutor");
    bytes32 private constant VERSION_HASH = keccak256("1");
    /// secp256k1n / 2, upper bound for non-malleable `s`.
    uint256 private constant MAX_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    DemoEscrow public immutable escrow;
    address public owner;
    address public platformSigner;
    mapping(address => bool) public isApprover;
    mapping(uint256 => bool) public nonceUsed;

    event GuardedRelease(
        bytes32 indexed intentHash,
        uint256 indexed escrowId,
        address indexed approver,
        uint256 nonce,
        bytes32 policyVersion,
        bytes32 evidenceHash
    );
    event ApproverSet(address indexed approver, bool allowed);
    event PlatformSignerSet(address indexed signer);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error ZeroAddress();
    error WrongEscrowContract();
    error NonceUsed(uint256 nonce);
    error IntentExpired();
    error ApprovalInvalid();
    error AuthorizationMismatch();
    error AuthorizationExpired();
    error AuthorizationInvalid();
    error TermsMismatch(string field);

    constructor(DemoEscrow escrow_, address platformSigner_) {
        escrow = escrow_;
        owner = msg.sender;
        platformSigner = platformSigner_;
        emit OwnershipTransferred(address(0), msg.sender);
        emit PlatformSignerSet(platformSigner_);
    }

    /* ------------------------------------------------------------------ */
    /* Execution                                                            */
    /* ------------------------------------------------------------------ */

    function execute(
        ReleaseIntent calldata intent,
        bytes calldata approvalSignature,
        Authorization calldata authorization,
        bytes calldata authorizationSignature
    ) external {
        if (intent.escrow != address(escrow)) revert WrongEscrowContract();
        if (nonceUsed[intent.nonce]) revert NonceUsed(intent.nonce);
        if (block.timestamp > intent.expiry) revert IntentExpired();

        bytes32 intentHash = intentDigest(intent);
        address approver = _recover(intentHash, approvalSignature);
        if (approver == address(0) || !isApprover[approver]) revert ApprovalInvalid();

        _verifyAuthorization(intent, intentHash, authorization, authorizationSignature);
        _verifyTerms(intent);

        nonceUsed[intent.nonce] = true;
        emit GuardedRelease(
            intentHash, intent.escrowId, approver, intent.nonce, intent.policyVersion, authorization.evidenceHash
        );
        escrow.release(intent.escrowId);
    }

    function _verifyAuthorization(
        ReleaseIntent calldata intent,
        bytes32 intentHash,
        Authorization calldata authorization,
        bytes calldata signature
    ) private view {
        if (
            authorization.intentHash != intentHash || authorization.nonce != intent.nonce
                || authorization.policyVersion != intent.policyVersion
        ) revert AuthorizationMismatch();
        if (block.timestamp > authorization.expiry) revert AuthorizationExpired();
        address signer = _recover(authorizationDigest(authorization), signature);
        if (signer == address(0) || signer != platformSigner) revert AuthorizationInvalid();
    }

    /// Defense in depth: even a correctly signed intent must match the chain.
    function _verifyTerms(ReleaseIntent calldata intent) private view {
        DemoEscrow.Escrow memory e = escrow.getEscrow(intent.escrowId);
        if (e.oracle != address(this)) revert TermsMismatch("oracle");
        if (e.state != DemoEscrow.State.Funded) revert TermsMismatch("state");
        if (e.seller != intent.beneficiary) revert TermsMismatch("beneficiary");
        if (e.token != intent.token) revert TermsMismatch("token");
        if (e.amount != intent.amount) revert TermsMismatch("amount");
        if (e.titleId != intent.titleId) revert TermsMismatch("titleId");
    }

    /* ------------------------------------------------------------------ */
    /* EIP-712                                                              */
    /* ------------------------------------------------------------------ */

    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    function intentDigest(ReleaseIntent memory i) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                RELEASE_INTENT_TYPEHASH,
                i.escrow,
                i.escrowId,
                i.titleId,
                i.token,
                i.beneficiary,
                i.amount,
                i.businessRef,
                i.policyVersion,
                i.nonce,
                i.expiry
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
    }

    function authorizationDigest(Authorization memory a) public view returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(AUTHORIZATION_TYPEHASH, a.intentHash, a.policyVersion, a.evidenceHash, a.nonce, a.expiry));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
    }

    /// Returns address(0) for any malformed or malleable signature, so a
    /// missing approval surfaces as ApprovalInvalid rather than a parse error.
    function _recover(bytes32 digest, bytes calldata sig) private pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(sig[64]);
        if (uint256(s) > MAX_S || (v != 27 && v != 28)) return address(0);
        return ecrecover(digest, v, r, s);
    }

    /* ------------------------------------------------------------------ */
    /* Admin                                                                */
    /* ------------------------------------------------------------------ */

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function setApprover(address approver, bool allowed) external onlyOwner {
        if (approver == address(0)) revert ZeroAddress();
        isApprover[approver] = allowed;
        emit ApproverSet(approver, allowed);
    }

    function setPlatformSigner(address signer) external onlyOwner {
        platformSigner = signer;
        emit PlatformSignerSet(signer);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
