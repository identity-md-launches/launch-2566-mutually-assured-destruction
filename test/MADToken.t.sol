// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Test fixture only: models the contract that creates and distributes a launch token.
contract MADFactoryFixture {
    function deploy() external returns (MADToken) {
        return new MADToken();
    }

    function deployDeterministic(bytes32 salt) external returns (MADToken) {
        return new MADToken{salt: salt}();
    }

    function distribute(MADToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

/// forge-config: default.fuzz.runs = 1000
contract MADTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    MADToken private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new MADToken();
    }

    function test_metadataAndWholeSupply() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_constructorEmitsExactlyOneMintEvent() public {
        vm.recordLogs();
        vm.prank(deployer);
        MADToken fresh = new MADToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(deployer))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_factoryReceivesEverythingNotTransactionOrigin() public {
        MADFactoryFixture factory = new MADFactoryFixture();
        vm.prank(alice, alice);
        MADToken fresh = factory.deploy();
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_create2DeploymentNeedsNoArgumentsOrExternalContracts() public {
        MADFactoryFixture factory = new MADFactoryFixture();
        bytes32 salt = keccak256("MAD deployment fixture");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(MADToken).creationCode))
                    )
                )
            )
        );
        MADToken fresh = factory.deployDeterministic(salt);
        assertEq(address(fresh), predicted);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
        assertLe(address(fresh).code.length, 24_576);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 123 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(deployer), SUPPLY - 123 ether);
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        _fund(alice, SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_selfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, deployer, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferInsufficientBalanceRevertsWithoutChanges() public {
        _fund(alice, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(alice);
        token.transfer(bob, 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferMaximumUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        for (uint256 amount; amount < 2; ++amount) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(deployer);
            token.transfer(address(0), amount);
        }
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
    }

    function test_approveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, spender, 100);
        _approve(alice, spender, 100);
        assertEq(token.allowance(alice, spender), 100);
        _approve(alice, spender, 30);
        assertEq(token.allowance(alice, spender), 30);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(alice);
        token.approve(address(0), 1);
    }

    function test_approveZeroCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 1);
    }

    function test_transferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        _fund(alice, 100);
        _approve(alice, spender, 80);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 30);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 30));
        assertEq(token.balanceOf(alice), 70);
        assertEq(token.balanceOf(bob), 30);
        assertEq(token.allowance(alice, spender), 50);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 50));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 80);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromUnlimitedAllowanceDoesNotDecreaseIt() public {
        _fund(alice, 100);
        _approve(alice, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 100));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 100);
    }

    function test_transferFromToSameHolderStillConsumesAllowance() public {
        _fund(alice, 100);
        _approve(alice, spender, 40);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 40));
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        _fund(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromByHolderStillRequiresAllowance() public {
        _fund(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
    }

    function test_transferFromOverAllowanceRevertsWithoutChanges() public {
        _fund(alice, 100);
        _approve(alice, spender, 20);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 20, 21));
        vm.prank(spender);
        token.transferFrom(alice, bob, 21);
        assertEq(token.allowance(alice, spender), 20);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_revokingAllowancePreventsFurtherSpending() public {
        _fund(alice, 100);
        _approve(alice, spender, type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, spender, 0);
        _approve(alice, spender, 0);
        assertEq(token.allowance(alice, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
    }

    function test_balanceFailureDoesNotConsumeAllowance() public {
        _fund(alice, 10);
        _approve(alice, spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(spender);
        token.transferFrom(alice, bob, 11);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_invalidRecipientDoesNotConsumeAllowance() public {
        _fund(alice, 100);
        _approve(alice, spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 40);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_noMintBurnFreezeOrUpgradeEntryPointsForAnyone() public {
        _fund(alice, 100);
        bytes[] memory calls = new bytes[](18);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[9] = abi.encodeWithSignature("lock(address)", alice);
        calls[10] = abi.encodeWithSignature("seize(address)", alice);
        calls[11] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[12] = abi.encodeWithSignature("initialize(address)", bob);
        calls[13] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[14] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[15] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[16] = abi.encodeWithSignature("setOwner(address)", bob);
        calls[17] = abi.encodeWithSignature("issue(uint256)", 1);
        address[2] memory callers = [deployer, bob];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < calls.length; ++j) {
                vm.prank(callers[i]);
                (bool success,) = address(token).call(calls[j]);
                assertFalse(success);
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(alice), 100);
                assertEq(token.balanceOf(bob), 0);
            }
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_nativeCurrencyAndUnknownCallsAreRejected() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool paid,) = address(token).call{value: 1 ether}("");
        assertFalse(paid);
        assertEq(address(token).balance, 0);
        (bool unknown,) = address(token).call(hex"12345678");
        assertFalse(unknown);
    }

    /// @dev Models the token legs of launch distribution, claims, buys and sells, not AMM pricing.
    function test_launchTransfersClaimsAndTradingLegsArriveWhole() public {
        MADFactoryFixture factory = new MADFactoryFixture();
        MADToken launched = factory.deploy();
        address distributor = makeAddr("distributor fixture");
        address poolManager = makeAddr("pool manager fixture");
        address requester = makeAddr("remainder recipient fixture");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY / 2;
        uint256 remainder = SUPPLY - swarm - pool;
        factory.distribute(launched, distributor, swarm);
        factory.distribute(launched, poolManager, pool);
        factory.distribute(launched, requester, remainder);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.balanceOf(requester), remainder);
        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarm));
        assertEq(launched.balanceOf(alice), swarm);
        assertEq(launched.balanceOf(distributor), 0);
        vm.prank(poolManager);
        assertTrue(launched.transfer(bob, 100 ether));
        assertEq(launched.balanceOf(bob), 100 ether);
        assertEq(launched.balanceOf(poolManager), pool - 100 ether);
        vm.prank(bob);
        assertTrue(launched.transfer(poolManager, 100 ether));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        if (recipient == address(0) || recipient == deployer) recipient = alice;
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransfer(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY);
        amount = bound(amount, 0, approval);
        _approve(deployer, spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        assertEq(token.allowance(deployer, spender), approval - amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferMoreThanBalanceReverts(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        _fund(alice, balance);
        uint256 amount = balance + excess;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_unauthorizedTransferFromReverts(uint256 allowance, uint256 excess) public {
        allowance = bound(allowance, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - allowance);
        _approve(deployer, spender, allowance);
        uint256 amount = allowance + excess;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, amount);
        assertEq(token.allowance(deployer, spender), allowance);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function _fund(address recipient, uint256 amount) private {
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
    }

    function _approve(address owner, address approvedSpender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(approvedSpender, amount));
    }
}
