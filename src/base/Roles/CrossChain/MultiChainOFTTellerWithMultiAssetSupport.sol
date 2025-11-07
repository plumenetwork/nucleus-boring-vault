// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {MultiChainTellerBase, MultiChainTellerBase_MessagesNotAllowedFrom} from "./MultiChainTellerBase.sol";
import {BridgeData, ERC20} from "./CrossChainTellerBase.sol";
import {OFTCoreAuth, IOFT, MessagingFee, MessagingReceipt, SendParam, OFTReceipt} from "./OAppAuth/OFTCoreAuth.sol";

import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title MultiChainOFTTellerWithMultiAssetSupport
 * @notice LayerZero OFT compatible implementation of MultiChainTeller
 */
contract MultiChainOFTTellerWithMultiAssetSupport is
    MultiChainTellerBase,
    OFTCoreAuth
{
    using OptionsBuilder for bytes;

    error MultiChainOFTTellerWithMultiAssetSupport_InvalidToken();

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        address _endpoint
    )
        MultiChainTellerBase(_owner, _vault, _accountant)
        OFTCoreAuth(ERC20(_vault).decimals(), _endpoint, _owner)
    { }

    /**
     * @inheritdoc IOFT
     */
    function token() external view returns (address) {
        return address(vault);
    }

    /**
     * @inheritdoc IOFT
     */
    function approvalRequired() external pure returns (bool) {
        return true;
    }

    /**
     * @inheritdoc IOFT
     * @dev Add the requiresAuth modifier to restrict access to authorized callers.
     */
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    )
        external
        payable
        override
        requiresAuth
        returns (
            MessagingReceipt memory msgReceipt,
            OFTReceipt memory oftReceipt
        )
    {
        // @dev Applies the token transfers regarding this send() operation.
        // - amountSentLD is the amount in local decimals that was ACTUALLY sent/debited from the sender.
        // - amountReceivedLD is the amount in local decimals that will be received/credited to the recipient on the remote OFT instance.
        (uint256 amountSentLD, uint256 amountReceivedLD) = _debit(
            msg.sender,
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.dstEid
        );

        // @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSentLD, amountReceivedLD);
    }

    /**
     * @notice function override to return the fee quote
     * @param shareAmount to be sent as a message
     * @param data Bridge data
     */
    function _quote(
        uint256 shareAmount,
        BridgeData calldata data
    ) internal view override returns (uint256) {
        bytes memory _message = abi.encodePacked(
            OFTMsgCodec.addressToBytes32(data.destinationChainReceiver),
            _toSD(shareAmount)
        );
        bytes memory _options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(data.messageGas, 0);

        if (address(data.bridgeFeeToken) != NATIVE) {
            revert MultiChainOFTTellerWithMultiAssetSupport_InvalidToken();
        }

        MessagingFee memory fee = _quote(
            data.chainSelector,
            _message,
            _options,
            false
        );

        return fee.nativeFee;
    }

    /**
     * @dev Internal function to perform a debit operation.
     * @param _from The address to debit.
     * @param _amountLD The amount to send in local decimals.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256,
        uint32
    )
        internal
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        // Since shares are directly burned, call `beforeTransfer` to enforce before transfer hooks.
        beforeTransfer(_from);

        // Burn shares from sender
        vault.exit(address(0), ERC20(address(0)), 0, _from, _amountLD);

        return (_amountLD, _amountLD);
    }

    /**
     * @dev Internal function to perform a credit operation.
     * @param _to The address to credit.
     * @param _amountLD The amount to credit in local decimals.
     * @param _srcEid The source endpoint ID.
     * @return amountReceivedLD The amount ACTUALLY received in local decimals.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal override returns (uint256 amountReceivedLD) {
        _beforeReceive();

        if (!selectorToChains[_srcEid].allowMessagesFrom) {
            revert MultiChainTellerBase_MessagesNotAllowedFrom(_srcEid);
        }

        // Decode the payload to get the message
        vault.enter(address(0), ERC20(address(0)), 0, _to, _amountLD);

        return _amountLD;
    }

    /**
     * @notice bridge override to allow bridge logic to be done for bridge() and depositAndBridge()
     * @param shareAmount to be moved across chain
     * @param data BridgeData
     */
    function _bridge(
        uint256 shareAmount,
        BridgeData calldata data
    ) internal override returns (bytes32) {
        if (address(data.bridgeFeeToken) != NATIVE) {
            revert MultiChainOFTTellerWithMultiAssetSupport_InvalidToken();
        }

        bytes memory _message = abi.encodePacked(
            OFTMsgCodec.addressToBytes32(data.destinationChainReceiver),
            _toSD(shareAmount)
        );
        bytes memory _options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(data.messageGas, 0);

        MessagingReceipt memory receipt = _lzSend(
            data.chainSelector,
            _message,
            _options,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender)
        );

        return receipt.guid;
    }
}
