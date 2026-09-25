// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/IPRegistry.sol";

/// @notice Deploys IPRegistry to whatever network you point --rpc-url at.
/// Usage:
///   forge script script/DeployIPRegistry.s.sol:DeployIPRegistry \
///     --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast --verify
contract DeployIPRegistry is Script {
    function run() external returns (IPRegistry) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        IPRegistry registry = new IPRegistry();
        vm.stopBroadcast();

        console.log("IPRegistry deployed at:", address(registry));
        return registry;
    }
}
