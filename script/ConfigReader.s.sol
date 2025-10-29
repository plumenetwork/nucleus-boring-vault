// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { console2 } from "forge-std/console2.sol";
import { VmSafe } from "forge-std/Vm.sol";

interface IAuthority {
    function setAuthority(address newAuthority) external;
    function transferOwnership(address newOwner) external;
    function setUserRole(address user, uint8 role, bool enabled) external;
    function doesUserHaveRole(address user, uint8 role) external view returns (bool);
    function owner() external view returns (address);
}

library ConfigReader {
    using StdJson for string;
    VmSafe private constant jsonVm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Config {
        address protocolAdmin;
        address base;
        uint8 boringVaultAndBaseDecimals;
        bytes32 accountantSalt;
        address boringVault;
        address payoutAddress;
        uint16 allowedExchangeRateChangeUpper;
        uint16 allowedExchangeRateChangeLower;
        uint32 minimumUpdateDelayInSeconds;
        uint16 managementFee;
        bytes32 boringVaultSalt;
        string boringVaultName;
        string boringVaultSymbol;
        bytes32 managerSalt;
        address balancerVault;
        bytes32 tellerSalt;
        uint32[] peerEid;
        address[] requiredDvns;
        address[] optionalDvns;
        uint64 dvnBlockConfirmationsRequired;
        uint8 optionalDvnThreshold;
        address accountant;
        address opMessenger;
        uint64 maxGasForPeer;
        uint64 minGasForPeer;
        address lzEndpoint;
        address mailbox;
        uint32 peerDomainId;
        bytes32 rolesAuthoritySalt;
        address manager;
        address teller;
        address predicateProxy;
        string tellerContractName;
        address operator;
        address strategist;
        address exchangeRateBot;
        address pauser;
        address rolesAuthority;
        bytes32 decoderSalt;
        address decoder;
        bytes32 rateProviderSalt;
        uint256 maxTimeFromLastUpdate;
        bool generateSalt;
        bool permissionedSalt;
        bool multichainRestricted;
        address[] assets;
        address[] rateProviders;
        address[] priceFeeds;
        address delegate;
    }

    function toConfig(string memory _config, string memory _chainConfig) internal view returns (Config memory config) {
        // Reading the 'protocolAdmin'
        config.protocolAdmin = _config.readAddress(".protocolAdmin");
        config.base = _config.readAddress(".base");
        config.boringVaultAndBaseDecimals = uint8(_config.readUint(".boringVaultAndBaseDecimals"));

        // Reading from the 'accountant' section
        config.accountant = _config.readAddress(".accountant.address");
        config.accountantSalt = _config.readBytes32(".accountant.accountantSalt");
        config.payoutAddress = _config.readAddress(".accountant.payoutAddress");
        config.allowedExchangeRateChangeUpper = uint16(_config.readUint(".accountant.allowedExchangeRateChangeUpper"));
        config.allowedExchangeRateChangeLower = uint16(_config.readUint(".accountant.allowedExchangeRateChangeLower"));
        config.minimumUpdateDelayInSeconds = uint32(_config.readUint(".accountant.minimumUpdateDelayInSeconds"));
        config.managementFee = uint16(_config.readUint(".accountant.managementFee"));

        // Reading from the 'boringVault' section
        config.boringVault = _config.readAddress(".boringVault.address");
        config.boringVaultSalt = _config.readBytes32(".boringVault.boringVaultSalt");
        config.boringVaultName = _config.readString(".boringVault.boringVaultName");
        config.boringVaultSymbol = _config.readString(".boringVault.boringVaultSymbol");

        // Reading from the 'manager' section
        config.manager = _config.readAddress(".manager.address");
        config.managerSalt = _config.readBytes32(".manager.managerSalt");

        // Reading from the 'teller' section
        config.teller = _config.readAddress(".teller.address");
        config.tellerSalt = _config.readBytes32(".teller.tellerSalt");
        config.maxGasForPeer = uint64(_config.readUint(".teller.maxGasForPeer"));
        config.minGasForPeer = uint64(_config.readUint(".teller.minGasForPeer"));
        config.tellerContractName = _config.readString(".teller.tellerContractName");
        config.assets = _config.readAddressArray(".teller.assets");
        config.predicateProxy = _config.readAddress(".teller.predicateProxy");

        // layerzero
        if (compareStrings(config.tellerContractName, "MultiChainLayerZeroTellerWithMultiAssetSupport")) {
            config.lzEndpoint = _chainConfig.readAddress(".lzEndpoint");
            config.peerEid = toUint32Array(_config.readUintArray(".teller.peerEid"));
            config.requiredDvns = _config.readAddressArray(".teller.dvnIfNoDefault.required");
            config.optionalDvns = _config.readAddressArray(".teller.dvnIfNoDefault.optional");
            config.dvnBlockConfirmationsRequired =
                uint64(_config.readUint(".teller.dvnIfNoDefault.blockConfirmationsRequiredIfNoDefault"));
            config.optionalDvnThreshold = uint8(_config.readUint(".teller.dvnIfNoDefault.optionalThreshold"));
        } else if (compareStrings(config.tellerContractName, "MultiChainHyperlaneTellerWithMultiAssetSupport")) {
            config.mailbox = _chainConfig.readAddress(".mailbox");
            config.peerDomainId = uint32(_config.readUint(".teller.peerDomainId"));
        }

        // Reading from the 'rolesAuthority' section
        config.rolesAuthority = _config.readAddress(".rolesAuthority.address");
        config.rolesAuthoritySalt = _config.readBytes32(".rolesAuthority.rolesAuthoritySalt");
        config.strategist = _config.readAddress(".rolesAuthority.strategist");
        config.exchangeRateBot = _config.readAddress(".rolesAuthority.exchangeRateBot");
        config.pauser = _config.readAddress(".rolesAuthority.pauser");
        config.operator = _config.readAddress(".rolesAuthority.operator");

        // Reading from the 'decoder' section
        config.decoderSalt = _config.readBytes32(".decoder.decoderSalt");
        config.decoder = _config.readAddress(".decoder.address");

        // Reading from the 'chainConfig' section
        config.balancerVault = _chainConfig.readAddress(".balancerVault");

        // Reading salt config
        config.generateSalt =  _config.readBool(".salt.generate");
        config.permissionedSalt =  _config.readBool(".salt.permissioned");
        config.multichainRestricted =  _config.readBool(".salt.multichainRestricted");

        try jsonVm.parseJsonAddress(_config, ".teller.delegate") returns (address delegateAddr) {
            config.delegate = delegateAddr;
        } catch {
            config.delegate = address(0);
        }

        return config;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    function toUint32Array(uint256[] memory input) public pure returns (uint32[] memory) {
        uint32[] memory output = new uint32[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            output[i] = uint32(input[i]);
        }
        return output;
    }
}
