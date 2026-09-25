// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title IPRegistry
/// @notice Mints datasets as NFTs and gates AI-agent access behind an on-chain
///         payment + role check. This is a hackathon prototype, not audited.
contract IPRegistry is ERC721, AccessControl, ReentrancyGuard {
    // ---------------------------------------------------------------------
    // Roles
    // ---------------------------------------------------------------------
    // NOTE FOR BEGINNERS: OpenZeppelin's AccessControl roles are GLOBAL per
    // address by default (hasRole(role, address) doesn't know about token IDs).
    // Since we need "licenser of asset #3" not just "a licenser somewhere",
    // we do NOT rely on hasRole() for per-asset licensing. Instead we keep
    // our own per-asset mappings below (licenserOf, consumerExpiry) and use
    // AccessControl only for the *global* admin role (who can mint at all,
    // if you choose to restrict it).
    bytes32 public constant LICENSER_ROLE = keccak256("LICENSER_ROLE");
    bytes32 public constant CONSUMER_ROLE = keccak256("CONSUMER_ROLE");

    uint256 public constant ACCESS_WINDOW = 1 days;

    // ---------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------
    uint256 private _nextId;

    mapping(uint256 => string) public cidOf;                 // assetId -> IPFS CID (ciphertext)
    mapping(uint256 => uint256) public priceOf;               // assetId -> price in wei
    mapping(uint256 => address) public licenserOf;             // assetId -> who can manage/revoke access
    mapping(uint256 => mapping(address => uint256)) public consumerExpiry; // assetId -> agent -> unix expiry
    mapping(uint256 => uint256) public escrowOf;               // assetId -> withdrawable wei owed to licenser

    // ---------------------------------------------------------------------
    // Events (this is the on-chain audit trail for the demo)
    // ---------------------------------------------------------------------
    event IPMinted(uint256 indexed assetId, address indexed creator, string cid, uint256 price);
    event AccessGranted(uint256 indexed assetId, address indexed agent, uint256 expiry);
    event AccessRevoked(uint256 indexed assetId, address indexed agent);
    event Withdrawn(uint256 indexed assetId, address indexed to, uint256 amount);

    constructor() ERC721("IPRegistry", "IPREG") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Minting
    // ---------------------------------------------------------------------
    /// @notice Any wallet can register a dataset as an NFT and become its licenser.
    /// @dev For the hackathon demo we allow open minting (any creator can mint).
    ///      If you want to restrict minting to approved creators, add
    ///      `onlyRole(DEFAULT_ADMIN_ROLE)` to this function's modifiers.
    function mintIP(string calldata cid, uint256 price) external returns (uint256 assetId) {
        assetId = _nextId++;
        _safeMint(msg.sender, assetId);

        cidOf[assetId] = cid;
        priceOf[assetId] = price;
        licenserOf[assetId] = msg.sender;

        _grantRole(LICENSER_ROLE, msg.sender); // global flag "this address licenses *something*"

        emit IPMinted(assetId, msg.sender, cid, price);
    }

    // ---------------------------------------------------------------------
    // Access purchase
    // ---------------------------------------------------------------------
    /// @notice An AI agent (or anyone) pays to unlock decryption-key access
    ///         to a dataset for ACCESS_WINDOW seconds.
    function requestAccess(uint256 assetId) external payable nonReentrant {
        require(_exists(assetId), "IPRegistry: asset does not exist");
        require(msg.value >= priceOf[assetId], "IPRegistry: insufficient payment");

        uint256 expiry = block.timestamp + ACCESS_WINDOW;
        consumerExpiry[assetId][msg.sender] = expiry;
        _grantRole(CONSUMER_ROLE, msg.sender);

        escrowOf[assetId] += msg.value; // credited to the licenser, withdrawable below

        emit AccessGranted(assetId, msg.sender, expiry);
    }

    /// @notice Licenser can cut off an agent's access early.
    function revokeAccess(uint256 assetId, address agent) external {
        require(msg.sender == licenserOf[assetId], "IPRegistry: not licenser");
        consumerExpiry[assetId][agent] = 0;
        emit AccessRevoked(assetId, agent);
    }

    /// @notice The check the AI agent calls before it will ask the key
    ///         manager for the decryption key. This is the single function
    ///         that gates the whole demo.
    function hasActiveAccess(uint256 assetId, address agent) public view returns (bool) {
        return consumerExpiry[assetId][agent] > block.timestamp;
    }

    // ---------------------------------------------------------------------
    // Payouts
    // ---------------------------------------------------------------------
    function withdraw(uint256 assetId) external nonReentrant {
        require(msg.sender == licenserOf[assetId], "IPRegistry: not licenser");
        uint256 amount = escrowOf[assetId];
        require(amount > 0, "IPRegistry: nothing to withdraw");

        escrowOf[assetId] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "IPRegistry: transfer failed");

        emit Withdrawn(assetId, msg.sender, amount);
    }

    // ---------------------------------------------------------------------
    // Required overrides (ERC721 + AccessControl both define supportsInterface)
    // ---------------------------------------------------------------------
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _exists(uint256 assetId) internal view returns (bool) {
        return _ownerOf(assetId) != address(0);
    }
}
