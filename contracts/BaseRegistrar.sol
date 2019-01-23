pragma solidity >=0.4.24;

import "@ensdomains/ens/contracts/ENS.sol";
import "@ensdomains/ens/contracts/HashRegistrar.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract BaseRegistrar is Ownable {
    uint constant public GRACE_PERIOD = 30 days;

    struct Registration {
        address owner;
        uint expiresAt; // Expiration timestamp
    }

    event ControllerAdded(address indexed controller);
    event ControllerRemoved(address indexed controller);
    event NameMigrated(bytes32 indexed hash, address indexed owner, uint expires);
    event NameRegistered(bytes32 indexed hash, address indexed owner, uint expires);
    event NameRenewed(bytes32 indexed hash, uint expires);
    event NameTransferred(bytes32 indexed hash, address indexed oldOwner, address indexed newOwner);

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

    // A map of name registrations.
    mapping(bytes32=>Registration) public registrations;

    // Authorises a controller, who can register and renew domains.
    function addController(address controller) external;

    // Revoke controller permission for an address.
    function removeController(address controller) external;

    // Returns the owner of the specified label hash.
    function nameOwner(bytes32 label) external view returns(address);

    // Returns the expiration timestamp of the specified label hash.
    function nameExpires(bytes32 label) external view returns(uint);

    // Returns true iff the specified name is available for registration.
    function available(bytes32 label) public view returns(bool);

    /**
     * @dev Register a name.
     */
    function register(bytes32 label, address owner, uint duration) external returns(uint);

    function renew(bytes32 label, uint duration) external returns(uint);

    /**
     * @dev Transfer ownership of a name to another account.
     */
    function transfer(bytes32 label, address newOwner) external;

    /**
     * @dev Reclaim ownership of a name in ENS, if you own it in the registrar.
     */
    function reclaim(bytes32 label) external;

    /**
     * @dev Transfers a registration from the initial registrar.
     * This function is called by the initial registrar when a user calls `transferRegistrars`.
     */
    function acceptRegistrarTransfer(bytes32 label, Deed deed, uint) external;
}
