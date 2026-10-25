// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "src/MADToken.sol";

/// @dev Complements the deployment/basic ERC-20 suite with adversarial sequences and algebraic properties.
/// forge-config: default.fuzz.runs = 1000
contract MADTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MADToken private token;
    address private owner;
    address private recipient;
    address private spender;
    address private otherSpender;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new MADToken();
        owner = makeAddr("adversarial holder");
        recipient = makeAddr("adversarial recipient");
        spender = makeAddr("adversarial spender");
        otherSpender = makeAddr("independent spender");
    }

    function test_oneWeiMovesExactlyByDelegationAndDirectTransfer() public {
        _fund(owner, 1);
        _approve(owner, spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, 1));
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.allowance(owner, spender), 0);
        vm.prank(recipient);
        assertTrue(token.transfer(owner, 1));
        assertEq(token.balanceOf(owner), 1);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumMinusOneApprovalIsFinite() public {
        _fund(owner, 1);
        _approve(owner, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, 1));
        assertEq(token.allowance(owner, spender), type(uint256).max - 2);
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedApprovalCannotTransferMaximumUint() public {
        _fund(owner, SUPPLY);
        _approve(owner, spender, type(uint256).max);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, type(uint256).max);
        assertEq(_stateDigest(), beforeState);
    }

    function test_exhaustedAllowanceRejectsReplayDespiteRemainingBalance() public {
        _fund(owner, 3);
        _approve(owner, spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, 1));
        assertEq(token.balanceOf(owner), 2);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.allowance(owner, spender), 0);
        bytes32 beforeReplay = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
        assertEq(_stateDigest(), beforeReplay);
    }

    function test_selfTransfersCannotExceedBalanceEvenWithApproval() public {
        _fund(owner, 1);
        _approve(owner, spender, 2);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, 1, 2));
        vm.prank(owner);
        token.transfer(owner, 2);
        assertEq(_stateDigest(), beforeState);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, 1, 2));
        vm.prank(spender);
        token.transferFrom(owner, owner, 2);
        assertEq(_stateDigest(), beforeState);
    }

    function test_ownerSpenderAndRecipientMayAllBeTheSameAccount() public {
        _fund(owner, 10);
        _approve(owner, owner, 7);
        vm.prank(owner);
        assertTrue(token.transferFrom(owner, owner, 7));
        assertEq(token.balanceOf(owner), 10);
        assertEq(token.allowance(owner, owner), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, owner, 0, 1));
        vm.prank(owner);
        token.transferFrom(owner, owner, 1);
        assertEq(token.balanceOf(owner), 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_replacingUnlimitedApprovalWithFiniteCapsFurtherSpending() public {
        _fund(owner, 10);
        _approve(owner, spender, type(uint256).max);
        _approve(owner, spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, 2));
        assertEq(token.allowance(owner, spender), 0);
        bytes32 afterSpend = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
        assertEq(_stateDigest(), afterSpend);
        assertEq(token.balanceOf(owner), 8);
        assertEq(token.balanceOf(recipient), 2);
    }

    function test_allowanceCannotBeBorrowedFromAnotherOwnerOrSpender() public {
        _fund(owner, 10);
        _fund(recipient, 10);
        _approve(owner, spender, 5);
        _approve(recipient, otherSpender, 7);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(recipient, owner, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1));
        vm.prank(otherSpender);
        token.transferFrom(owner, recipient, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function test_receivingItsOwnSupplyDoesNotBurnTokens() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_knownMutatorsRejectEtherAtomically() public {
        _prepareRawCalls();
        vm.deal(address(this), 3);
        bytes32 beforeState = _stateDigest();
        for (uint256 i; i < 3; ++i) {
            (bool success,) = address(token).call{value: 1}(_mutationCall(i));
            assertFalse(success, "ERC-20 mutator accepted native value");
            assertEq(_stateDigest(), beforeState);
        }
        assertEq(address(this).balance, 3);
        assertEq(address(token).balance, 0);
    }

    function testFuzz_truncatedMutatorCalldataRevertsAtomically(uint256 operation, uint256 length) public {
        _prepareRawCalls();
        bytes memory data = _mutationCall(operation % 3);
        length = bound(length, 0, data.length - 1);
        // Keep a real selector (when length >= 4) but remove at least one required ABI byte.
        assembly ("memory-safe") {
            mstore(data, length)
        }
        bytes32 beforeState = _stateDigest();
        (bool success,) = address(token).call(data);
        assertFalse(success, "truncated mutation was accepted");
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_failedDelegationCanBeRetriedAfterFunding(uint256 balance, uint256 shortfall, bool unlimited)
        public
    {
        balance = bound(balance, 0, SUPPLY - 1);
        shortfall = bound(shortfall, 1, SUPPLY - balance);
        uint256 amount = balance + shortfall;
        uint256 approval = unlimited ? type(uint256).max : amount;
        _fund(owner, balance);
        _approve(owner, spender, approval);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
        assertEq(_stateDigest(), beforeState);

        // No new approval: the allowance from the rejected call must remain usable.
        _fund(owner, shortfall);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.allowance(owner, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedRecipientCanBeCorrectedWithoutReapproval(uint256 amount, uint256 approval) public {
        amount = bound(amount, 1, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        _fund(owner, amount);
        _approve(owner, spender, approval);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
        assertEq(_stateDigest(), beforeState);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.allowance(owner, spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementIsIsolatedAndIdempotent(uint256 first, uint256 replacement) public {
        _approve(owner, otherSpender, 17);
        _approve(recipient, spender, 23);
        _approve(owner, spender, first);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(owner, spender, replacement);
        _approve(owner, spender, replacement);
        assertEq(token.allowance(owner, spender), replacement);
        bytes32 once = _stateDigest();
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(owner, spender, replacement);
        _approve(owner, spender, replacement);
        assertEq(_stateDigest(), once);
        assertEq(token.allowance(owner, otherSpender), 17);
        assertEq(token.allowance(recipient, spender), 23);
        assertEq(token.allowance(spender, owner), 0);
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalancesAndAuthorizations(
        uint256 ownerBalance,
        uint256 recipientBalance,
        uint256 amount,
        uint256 approval
    ) public {
        ownerBalance = bound(ownerBalance, 0, SUPPLY);
        recipientBalance = bound(recipientBalance, 0, SUPPLY - ownerBalance);
        amount = bound(amount, 0, ownerBalance);
        _fund(owner, ownerBalance);
        _fund(recipient, recipientBalance);
        _approve(owner, spender, approval);
        _approve(recipient, otherSpender, ~approval);
        bytes32 beforeState = _stateDigest();
        vm.prank(owner);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(owner), ownerBalance - amount);
        assertEq(token.balanceOf(recipient), recipientBalance + amount);
        vm.prank(recipient);
        assertTrue(token.transfer(owner, amount));
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_splitDelegatedSpendingMatchesSingleSpend(uint256 first, uint256 second, uint256 approval) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        uint256 total = first + second;
        if (approval < total) approval = total;
        MADToken singleSpend = new MADToken();
        assertTrue(singleSpend.transfer(owner, total));
        _fund(owner, total);
        vm.prank(owner);
        assertTrue(singleSpend.approve(spender, approval));
        _approve(owner, spender, approval);

        vm.startPrank(spender);
        assertTrue(token.transferFrom(owner, recipient, first));
        assertTrue(token.transferFrom(owner, recipient, second));
        assertTrue(singleSpend.transferFrom(owner, recipient, total));
        vm.stopPrank();
        assertEq(token.balanceOf(owner), singleSpend.balanceOf(owner));
        assertEq(token.balanceOf(recipient), singleSpend.balanceOf(recipient));
        assertEq(token.balanceOf(address(this)), singleSpend.balanceOf(address(this)));
        assertEq(token.allowance(owner, spender), singleSpend.allowance(owner, spender));
        assertEq(token.balanceOf(recipient), total);
        assertEq(token.allowance(owner, spender), approval == type(uint256).max ? approval : approval - total);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleSpend.totalSupply(), SUPPLY);
    }

    function _fund(address to, uint256 amount) private {
        assertTrue(token.transfer(to, amount));
    }

    function _approve(address from, address approved, uint256 amount) private {
        vm.prank(from);
        assertTrue(token.approve(approved, amount));
    }

    function _prepareRawCalls() private {
        _fund(owner, 2);
        _approve(owner, address(this), 2);
        _approve(address(this), spender, 17);
    }

    function _mutationCall(uint256 operation) private view returns (bytes memory) {
        if (operation == 0) return abi.encodeCall(token.transfer, (recipient, 1));
        if (operation == 1) return abi.encodeCall(token.approve, (spender, 1));
        return abi.encodeCall(token.transferFrom, (owner, recipient, 1));
    }

    /// @dev Snapshot all balances and authorization pairs reachable in this fixture. This compares
    /// observable state across operations; it does not read storage slots or derive expected state
    /// from the token's internal implementation.
    function _stateDigest() private view returns (bytes32 digest) {
        address[7] memory accounts =
            [address(this), owner, recipient, spender, otherSpender, address(token), address(0)];
        digest = keccak256(abi.encode(token.name(), token.symbol(), token.decimals(), token.totalSupply()));
        for (uint256 i; i < accounts.length; ++i) {
            digest = keccak256(abi.encode(digest, token.balanceOf(accounts[i])));
            for (uint256 j; j < accounts.length; ++j) {
                digest = keccak256(abi.encode(digest, token.allowance(accounts[i], accounts[j])));
            }
        }
    }
}
