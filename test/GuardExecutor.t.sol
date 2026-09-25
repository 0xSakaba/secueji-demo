// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";
import {GuardExecutor} from "../src/GuardExecutor.sol";

/// Each test names the MVP Spec scenario (S-xxx) or acceptance criterion (AC-xxx) it covers.
contract GuardExecutorTest is Test {
    uint256 constant APPROVER_PK = 0xA11CE;
    uint256 constant PLATFORM_PK = 0xB0B;
    uint256 constant OUTSIDER_PK = 0xBAD;
    uint256 constant AMOUNT = 18_450e6;
    bytes32 constant TITLE = keccak256("title-001");
    bytes32 constant POLICY = keccak256("policy-v1");
    bytes32 constant BUSINESS_REF = keccak256("order-001/payment-001");
    bytes32 constant EVIDENCE = keccak256("evidence-bundle-001");

    address buyer = address(0xB0);
    address seller = address(0x5E11);
    address legacyOracle = address(0x0AC1E);

    DemoStablecoin token;
    DemoEscrow escrow;
    GuardExecutor guard;
    address approver;
    address platformSigner;

    function setUp() public {
        approver = vm.addr(APPROVER_PK);
        platformSigner = vm.addr(PLATFORM_PK);
        token = new DemoStablecoin();
        escrow = new DemoEscrow();
        guard = new GuardExecutor(escrow, platformSigner);
        guard.setApprover(approver, true);
        token.mint(buyer, AMOUNT * 10);
    }

    /* ---------------------------------------------------------------- */
    /* Guarded mode                                                      */
    /* ---------------------------------------------------------------- */

    /// S-001, AC-001, AC-008: valid exact-intent release pays the seller once.
    function test_S001_validGuardedRelease() public {
        uint256 id = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(id, 1);
        (GuardExecutor.Authorization memory auth, bytes memory authSig) = _authorize(intent);

        guard.execute(intent, _signIntent(APPROVER_PK, intent), auth, authSig);

        require(token.balanceOf(seller) == AMOUNT, "seller not paid");
        require(token.balanceOf(address(escrow)) == 0, "escrow still holds funds");
        require(escrow.getEscrow(id).state == DemoEscrow.State.Released, "not released");
        require(guard.nonceUsed(1), "nonce not consumed");
    }

    /// S-002 guarded, AC-002: no approval signature means no release.
    function test_S002_guardedRejectsMissingApproval() public {
        uint256 id = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(id, 1);
        (GuardExecutor.Authorization memory auth, bytes memory authSig) = _authorize(intent);

        vm.expectRevert(GuardExecutor.ApprovalInvalid.selector);
        guard.execute(intent, "", auth, authSig);
    }

    /// AC-002: a signature from someone who is not a registered approver is rejected.
    function test_AC002_rejectsNonApproverSignature() public {
        uint256 id = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(id, 1);
        (GuardExecutor.Authorization memory auth, bytes memory authSig) = _authorize(intent);

        bytes memory approvalSig = _signIntent(OUTSIDER_PK, intent);

        vm.expectRevert(GuardExecutor.ApprovalInvalid.selector);

        guard.execute(intent, approvalSig, auth, authSig);
    }

    /// AC-007: the old oracle EOA cannot release a guarded escrow directly.
    function test_AC007_oracleEoaCannotReleaseGuardedEscrow() public {
        uint256 id = _createFunded(address(guard));
        vm.prank(legacyOracle);
        vm.expectRevert(DemoEscrow.NotOracle.selector);
        escrow.release(id);
    }

    /// S-003, AC-003: an intent that disagrees with on-chain terms is rejected even
    /// if both approver and platform signed it.
    function test_S003_rejectsBeneficiaryMismatch() public {
        _expectTermsMismatch(0, "beneficiary");
    }

    function test_S003_rejectsAmountMismatch() public {
        _expectTermsMismatch(1, "amount");
    }

    function test_S003_rejectsTokenMismatch() public {
        _expectTermsMismatch(2, "token");
    }

    function test_S003_rejectsTitleMismatch() public {
        _expectTermsMismatch(3, "titleId");
    }

    /// S-004, AC-005: a used nonce cannot be replayed, even against a different funded escrow.
    function test_S004_rejectsNonceReplay() public {
        uint256 first = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(first, 7);
        (GuardExecutor.Authorization memory auth, bytes memory authSig) = _authorize(intent);
        guard.execute(intent, _signIntent(APPROVER_PK, intent), auth, authSig);

        uint256 second = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory replay = _intent(second, 7);
        (GuardExecutor.Authorization memory auth2, bytes memory authSig2) = _authorize(replay);

        bytes memory approvalSig = _signIntent(APPROVER_PK, replay);

        vm.expectRevert(abi.encodeWithSelector(GuardExecutor.NonceUsed.selector, 7));

        guard.execute(replay, approvalSig, auth2, authSig2);
        require(escrow.getEscrow(second).state == DemoEscrow.State.Funded, "second escrow moved");
    }

    /// AC-006: an expired platform authorization cannot execute.
    function test_AC006_rejectsExpiredAuthorization() public {
        uint256 id = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(id, 1);
        (GuardExecutor.Authorization memory auth, bytes memory authSig) = _authorize(intent);
        bytes memory approvalSig = _signIntent(APPROVER_PK, intent);

        vm.warp(auth.expiry + 1);
        vm.expectRevert(GuardExecutor.AuthorizationExpired.selector);
        guard.execute(intent, approvalSig, auth, authSig);
    }

    function test_rejectsExpiredIntent() public {
        uint256 id = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(id, 1);
        (GuardExecutor.Authorization memory auth, bytes memory authSig) = _authorize(intent);
        bytes memory approvalSig = _signIntent(APPROVER_PK, intent);

        vm.warp(intent.expiry + 1);
        vm.expectRevert(GuardExecutor.IntentExpired.selector);
        guard.execute(intent, approvalSig, auth, authSig);
    }

    /// Approval and authorization must bind the same intent (MVP Spec question 3).
    function test_rejectsAuthorizationForDifferentIntent() public {
        uint256 id = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(id, 1);
        GuardExecutor.ReleaseIntent memory other = _intent(id, 1);
        other.businessRef = keccak256("another-order");
        (GuardExecutor.Authorization memory auth, bytes memory authSig) = _authorize(other);

        bytes memory approvalSig = _signIntent(APPROVER_PK, intent);

        vm.expectRevert(GuardExecutor.AuthorizationMismatch.selector);

        guard.execute(intent, approvalSig, auth, authSig);
    }

    function test_rejectsAuthorizationFromWrongSigner() public {
        uint256 id = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(id, 1);
        (GuardExecutor.Authorization memory auth,) = _authorize(intent);
        bytes memory forged = _sign(OUTSIDER_PK, guard.authorizationDigest(auth));

        bytes memory approvalSig = _signIntent(APPROVER_PK, intent);

        vm.expectRevert(GuardExecutor.AuthorizationInvalid.selector);

        guard.execute(intent, approvalSig, auth, forged);
    }

    function test_rejectsOtherEscrowContract() public {
        uint256 id = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(id, 1);
        intent.escrow = address(0xDEAD);
        (GuardExecutor.Authorization memory auth, bytes memory authSig) = _authorize(intent);

        bytes memory approvalSig = _signIntent(APPROVER_PK, intent);

        vm.expectRevert(GuardExecutor.WrongEscrowContract.selector);

        guard.execute(intent, approvalSig, auth, authSig);
    }

    function test_cannotRegisterZeroAddressApprover() public {
        vm.expectRevert(GuardExecutor.ZeroAddress.selector);
        guard.setApprover(address(0), true);
    }

    /* ---------------------------------------------------------------- */
    /* Helpers                                                           */
    /* ---------------------------------------------------------------- */

    function _createFunded(address oracle) internal returns (uint256 id) {
        id = escrow.createEscrow(buyer, seller, address(token), AMOUNT, TITLE, oracle);
        vm.prank(buyer);
        token.approve(address(escrow), AMOUNT);
        vm.prank(buyer);
        escrow.fund(id);
    }

    function _intent(uint256 escrowId, uint256 nonce) internal view returns (GuardExecutor.ReleaseIntent memory) {
        return GuardExecutor.ReleaseIntent({
            escrow: address(escrow),
            escrowId: escrowId,
            titleId: TITLE,
            token: address(token),
            beneficiary: seller,
            amount: AMOUNT,
            businessRef: BUSINESS_REF,
            policyVersion: POLICY,
            nonce: nonce,
            expiry: block.timestamp + 1 hours
        });
    }

    function _authorize(GuardExecutor.ReleaseIntent memory intent)
        internal
        view
        returns (GuardExecutor.Authorization memory auth, bytes memory sig)
    {
        auth = GuardExecutor.Authorization({
            intentHash: guard.intentDigest(intent),
            policyVersion: intent.policyVersion,
            evidenceHash: EVIDENCE,
            nonce: intent.nonce,
            expiry: block.timestamp + 10 minutes
        });
        sig = _sign(PLATFORM_PK, guard.authorizationDigest(auth));
    }

    function _signIntent(uint256 pk, GuardExecutor.ReleaseIntent memory intent) internal view returns (bytes memory) {
        return _sign(pk, guard.intentDigest(intent));
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// field: 0 beneficiary, 1 amount, 2 token, 3 titleId
    function _expectTermsMismatch(uint256 field, string memory name) internal {
        uint256 id = _createFunded(address(guard));
        GuardExecutor.ReleaseIntent memory intent = _intent(id, 1);
        if (field == 0) intent.beneficiary = address(0xA77AC);
        else if (field == 1) intent.amount = AMOUNT - 1;
        else if (field == 2) intent.token = address(new DemoStablecoin());
        else intent.titleId = keccak256("other-title");
        (GuardExecutor.Authorization memory auth, bytes memory authSig) = _authorize(intent);

        bytes memory approvalSig = _signIntent(APPROVER_PK, intent);

        vm.expectRevert(abi.encodeWithSelector(GuardExecutor.TermsMismatch.selector, name));

        guard.execute(intent, approvalSig, auth, authSig);
        require(token.balanceOf(seller) == 0, "seller paid on mismatch");
    }
}
