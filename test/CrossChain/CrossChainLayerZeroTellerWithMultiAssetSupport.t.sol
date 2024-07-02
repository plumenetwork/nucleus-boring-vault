// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {CrossChainBaseTest, CrossChainTellerBase} from "./CrossChainBase.t.sol";
import {CrossChainLayerZeroTellerWithMultiAssetSupport} from "src/base/Roles/CrossChain/CrossChainLayerZeroTellerWithMultiAssetSupport.sol";
import "src/interfaces/ICrossChainTeller.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {console} from "@forge-std/Test.sol";

import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {OAppAuthCore} from "src/base/Roles/CrossChain/OAppAuth/OAppAuthCore.sol";

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
contract CrossChainLayerZeroTellerWithMultiAssetSupportTest is CrossChainBaseTest, TestHelperOz5{
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint;

    uint constant MAX_BRIDGE_FEE = 100_000;

    function setUp() public virtual override(CrossChainBaseTest, TestHelperOz5){
        CrossChainBaseTest.setUp();
        TestHelperOz5.setUp();
    }

    function testBridgingShares(uint256 sharesToBridge) external {
        sharesToBridge = uint96(bound(sharesToBridge, 1, 1_000e18));
        uint256 startingShareBalance = boringVault.balanceOf(address(this));
        // Setup chains on bridge.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000);

        // Bridge 100 shares.
        address to = vm.addr(1);

        // TODO 
        // - fee token must be WETH (or LZO?)
        BridgeData memory data = BridgeData({
            chainId: DESTINATION_SELECTOR,
            destinationChainReceiver: to,
            bridgeFeeToken: WETH,
            maxBridgeFee: MAX_BRIDGE_FEE,
            data: ""
        });

        bytes32 id = sourceTeller.bridge{value:sourceTeller.previewFee(sharesToBridge, data)}(sharesToBridge, data);

        verifyPackets(uint32(DESTINATION_SELECTOR), addressToBytes32(address(destinationTeller)));

        assertEq(
            boringVault.balanceOf(address(this)), startingShareBalance - sharesToBridge, "Should have burned shares."
        );

        assertEq(
            boringVault.balanceOf(to), sharesToBridge
        );
    }

    function testDepositAndBridge(uint256 amount) external{
        uint256 startingShareBalance = boringVault.balanceOf(address(this));

        amount = bound(amount, 0.0001e18, 10_000e18);
        // make a user and give them WETH
        address user = makeAddr("A user");
        address userChain2 = makeAddr("A user on chain 2");
        deal(address(WETH), user, amount);

        // approve teller to spend WETH
        vm.startPrank(user);
        WETH.approve(address(sourceTeller), amount);

        // preform depositAndBridge
        BridgeData memory data = BridgeData({
            chainId: DESTINATION_SELECTOR,
            destinationChainReceiver: userChain2,
            bridgeFeeToken: WETH,
            maxBridgeFee: MAX_BRIDGE_FEE,
            data: ""
        });

        uint ONE_SHARE = 10 ** boringVault.decimals();

        // so you don't really need to know exact shares in reality
        // just need to pass in a number roughly the same size to get quote
        // I still get the real number here for testing
        uint shares = amount.mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(WETH));
        uint quote = sourceTeller.previewFee(shares, data);
        sourceTeller.depositAndBridge{value:quote}(WETH, amount, shares, data);

        verifyPackets(uint32(DESTINATION_SELECTOR), addressToBytes32(address(destinationTeller)));

        assertEq(
            boringVault.balanceOf(address(this)), startingShareBalance - shares, "Should have burned shares."
        );

        assertEq(
            boringVault.balanceOf(userChain2), shares
        );
    }


    function testReverts() external {
        // Adding a chain with a zero message gas limit should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport_ZeroMessageGasLimit.selector))
        );
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 0);

        // Allowing messages to a chain with a zero message gas limit should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport_ZeroMessageGasLimit.selector))
        );
        sourceTeller.allowMessagesToChain(DESTINATION_SELECTOR, address(destinationTeller), 0);

        // Changing the gas limit to zero should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport_ZeroMessageGasLimit.selector))
        );
        sourceTeller.setChainGasLimit(DESTINATION_SELECTOR, 0);

        // But you can add a chain with a non-zero message gas limit, if messages to are not supported.
        uint32 newChainSelector = 3;
        sourceTeller.addChain(newChainSelector, true, false, address(destinationTeller), 0);

        // If teller is paused bridging is not allowed.
        sourceTeller.pause();
        vm.expectRevert(
            bytes(abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__Paused.selector))
        );

        BridgeData memory data = BridgeData(DESTINATION_SELECTOR, address(0), ERC20(address(0)), MAX_BRIDGE_FEE, "");
        sourceTeller.bridge(0, data);

        sourceTeller.unpause();

        // Trying to send messages to a chain that is not supported should revert.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CrossChainLayerZeroTellerWithMultiAssetSupport_MessagesNotAllowedTo.selector, DESTINATION_SELECTOR
                )
            )
        );

        data = BridgeData(DESTINATION_SELECTOR, address(this), WETH, MAX_BRIDGE_FEE, abi.encode(DESTINATION_SELECTOR));
        sourceTeller.bridge(1e18, data);

        // setup chains.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000);


        // if the token is not WETH, should revert
        address NOT_WETH = 0xfAbA6f8e4a5E8Ab82F62fe7C39859FA577269BE3;
        data = BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NOT_WETH), MAX_BRIDGE_FEE, abi.encode(DESTINATION_SELECTOR));
        vm.expectRevert(
            abi.encodeWithSelector(
                CrossChainLayerZeroTellerWithMultiAssetSupport_InvalidToken.selector
            )
        );
        sourceTeller.bridge(1e18, data);

        // If the max fee is exceeded the transaction should revert.
        uint quote = sourceTeller.previewFee(1e18, data);
        data = BridgeData(DESTINATION_SELECTOR, address(this), WETH, quote-1, abi.encode(DESTINATION_SELECTOR));
        vm.expectRevert(
            abi.encodeWithSelector(
                CrossChainLayerZeroTellerWithMultiAssetSupport_TxExceedsMaxBridgeFee.selector, quote-1, quote
            )
        );
        sourceTeller.bridge{value:quote-1}(1e18, data);

        // Call now succeeds.
        data = BridgeData(DESTINATION_SELECTOR, address(this), WETH, quote, abi.encode(DESTINATION_SELECTOR));
        sourceTeller.bridge{value:quote}(1e18, data);

    }

    function _deploySourceAndDestinationTeller() internal override{

        setUpEndpoints(2, LibraryType.UltraLightNode);

        sourceTeller = CrossChainLayerZeroTellerWithMultiAssetSupport(
            _deployOApp(type(CrossChainLayerZeroTellerWithMultiAssetSupport).creationCode, abi.encode(address(this), address(boringVault), address(accountant), address(WETH), endpoints[uint32(SOURCE_SELECTOR)]))
        );

        destinationTeller = CrossChainLayerZeroTellerWithMultiAssetSupport(
            _deployOApp(type(CrossChainLayerZeroTellerWithMultiAssetSupport).creationCode, abi.encode(address(this), address(boringVault), address(accountant), address(WETH), endpoints[uint32(DESTINATION_SELECTOR)]))
        );

        // config and wire the oapps
        address[] memory oapps = new address[](2);
        oapps[0] = address(sourceTeller);
        oapps[1] = address(destinationTeller);
        this.wireOApps(oapps);

        bytes32 peer1 = OAppAuthCore(address(sourceTeller)).peers(uint32(DESTINATION_SELECTOR));
        bytes32 peer2 = OAppAuthCore(address(destinationTeller)).peers(uint32(SOURCE_SELECTOR));

    }

}
