pragma solidity >=0.4.24;

import "@ensdomains/ens/contracts/ENS.sol";
import "@ensdomains/ens/contracts/HashRegistrar.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract BaseRegistrar is ERC721, Ownable {
    uint constant public GRACE_PERIOD = 30 days;

    event ControllerAdded(address indexed controller);
    event ControllerRemoved(address indexed controller);
    event NameMigrated(uint256 indexed id, address indexed owner, uint expires);
    event NameRegistered(uint256 indexed id, address indexed owner, uint expires);
    event NameRenewed(uint256 indexed id, uint expires);

    // Expiration timestamp for migrated domains.
    uint public transferPeriodEnds;

    // The ENS registry
    ENS public ens;

    // The namehash of the TLD this registrar owns (eg, .eth)
    bytes32 public baseNode;

    // The interim registrar
    HashRegistrar public previousRegistrar;

    // A map of addresses that are authorised to register and renew names.
    mapping(address=>bool) public controllers;

    // Authorises a controller, who can register and renew domains.
    function addController(address controller) external;

    // Revoke controller permission for an address.
    function removeController(address controller) external;

    // Returns the expiration timestamp of the specified label hash.
    function nameExpires(uint256 id) external view returns(uint);

    // Returns true iff the specified name is available for registration.
    function available(uint256 id) public view returns(bool);

    /**
     * @dev Register a name.
     */
    function register(uint256 id, address owner, uint duration) external returns(uint);

    function renew(uint256 id, uint duration) external returns(uint);

    /**
     * @dev Reclaim ownership of a name in ENS, if you own it in the registrar.
     */
    function reclaim(uint256 id) external;

    /**
     * @dev Transfers a registration from the initial registrar.
     * This function is called by the initial registrar when a user calls `transferRegistrars`.
     */
    function acceptRegistrarTransfer(bytes32 label, Deed deed, uint) external;
}
