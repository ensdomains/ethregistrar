pragma solidity ^0.5.0;

import "@ensdomains/ens/contracts/ENS.sol";
import "@ensdomains/ens/contracts/Registrar.sol";
import "@ensdomains/ens/contracts/HashRegistrar.sol";
import "./BaseRegistrar.sol";
import "./ERC721TokenReceiver.sol";

contract BaseRegistrarImplementation is BaseRegistrar {
    mapping(address=>mapping(address=>bool)) operators;
    mapping(address=>uint) ownershipCount;

    constructor(ENS _ens, bytes32 _baseNode, uint _transferPeriodEnds) public {
        ens = _ens;
        baseNode = _baseNode;
        previousRegistrar = HashRegistrar(ens.owner(baseNode));
        transferPeriodEnds = _transferPeriodEnds;
    }

    modifier live {
        require(ens.owner(baseNode) == address(this));
        _;
    }

    modifier owns(uint256 id) {
        require(registrations[id].expiresAt > now);
        require(registrations[id].owner == msg.sender // Caller is the owner
            || registrations[id].approval == msg.sender // Caller is approved for this name
            || operators[registrations[id].owner][msg.sender] // Caller is approved for all names
        );
        _;
    }

    modifier onlyController {
        require(controllers[msg.sender]);
        _;
    }

    // Authorises a controller, who can register and renew domains.
    function addController(address controller) external onlyOwner {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    // Revoke controller permission for an address.
    function removeController(address controller) external onlyOwner {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    // Returns the expiration timestamp of the specified registration.
    function nameExpires(uint256 id) external view returns(uint) {
        return registrations[id].expiresAt;
    }

    // Returns true iff the specified name is available for registration.
    function available(uint256 id) public view returns(bool) {
        // Not available if it's registered here.
        if(registrations[id].expiresAt + GRACE_PERIOD >= now) {
            return false;
        }
        // Available if we're past the transfer period, or the name isn't
        // registered in the legacy registrar.
        return now > transferPeriodEnds || previousRegistrar.state(bytes32(id)) == Registrar.Mode.Open;
    }

    /**
     * @dev Register a name.
     */
    function register(uint256 id, address owner, uint duration) external live onlyController returns(uint) {
        require(available(id));
        require(now + duration + GRACE_PERIOD > duration); // Check for overflow

        registrations[id].expiresAt = now + duration;
        _transfer(address(0), owner, id);

        emit NameRegistered(id, owner, now + duration);

        ens.setSubnodeOwner(baseNode, bytes32(id), owner);

        return now + duration;
    }

    function renew(uint256 id, uint duration) external live onlyController returns(uint) {
        require(!available(id));
        require(registrations[id].expiresAt + duration + GRACE_PERIOD > duration); // Check for overflow

        registrations[id].expiresAt += duration;
        emit NameRenewed(id, registrations[id].expiresAt);
        return registrations[id].expiresAt;
    }

    /**
     * @dev Reclaim ownership of a name in ENS, if you own it in the registrar.
     */
    function reclaim(uint256 id) external owns(id) live {
        ens.setSubnodeOwner(baseNode, bytes32(id), registrations[id].owner);
    }

    /**
     * @dev Transfers a registration from the initial registrar.
     * This function is called by the initial registrar when a user calls `transferRegistrars`.
     */
    function acceptRegistrarTransfer(bytes32 label, Deed deed, uint) external {
        uint256 id = uint256(label);

        require(msg.sender == address(previousRegistrar));
        require(registrations[id].owner == address(0));
        require(transferPeriodEnds > now);

        address owner = deed.owner();
        // Destroy the deed and transfer the funds back to the registrant.
        deed.closeDeed(1000);
        // Register the name
        registrations[id].expiresAt = transferPeriodEnds;
        _transfer(address(0), owner, id);

        emit NameRegistered(id, owner, transferPeriodEnds);

        ens.setSubnodeOwner(baseNode, bytes32(id), owner);
    }


    /// @notice Find the owner of an NFT
    /// @dev NFTs assigned to zero address are considered invalid, and queries
    ///  about them do throw.
    /// @param id The identifier for an NFT
    /// @return The address of the owner of the NFT
    function ownerOf(uint256 id) public view returns(address) {
        if(registrations[id].expiresAt + GRACE_PERIOD >= now) {
            return registrations[id].owner;
        } else {
            return address(0);
        }
    }

    /// @notice Count all NFTs assigned to an owner
    /// @dev NFTs assigned to the zero address are considered invalid, and this
    ///  function throws for queries about the zero address.
    /// @param _owner An address for whom to query the balance
    /// @return The number of NFTs owned by `_owner`, possibly zero
    function balanceOf(address _owner) external view returns (uint256) {
        return ownershipCount[_owner];
    }

    /// @notice Transfers the ownership of a registration from one address to another address
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `id` is not a valid NFT. When transfer is complete, this function
    ///  checks if `_to` is a smart contract (code size > 0). If so, it calls
    ///  `onERC721Received` on `_to` and throws if the return value is not
    ///  `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param id The NFT to transfer
    /// @param data Additional data with no specified format, sent in call to `_to`
    function safeTransferFrom(address _from, address _to, uint256 id, bytes memory data) public payable owns(id) {
        require(_from == registrations[id].owner);
        require(_to != address(0));
        _transfer(_from, _to, id);
        if(isContract(_to)) {
            require(ERC721TokenReceiver(_to).onERC721Received(msg.sender, _from, id, data) == bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")));
        }
    }

    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @dev This works identically to the other function with an extra data parameter,
    ///  except this function just sets data to "".
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param id The NFT to transfer
    function safeTransferFrom(address _from, address _to, uint256 id) external payable {
        safeTransferFrom(_from, _to, id, "");
    }

    /// @notice Transfer ownership of an NFT -- THE CALLER IS RESPONSIBLE
    ///  TO CONFIRM THAT `_to` IS CAPABLE OF RECEIVING NFTS OR ELSE
    ///  THEY MAY BE PERMANENTLY LOST
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `id` is not a valid NFT.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param id The NFT to transfer
    function transferFrom(address _from, address _to, uint256 id) external payable owns(id) {
        require(_from == registrations[id].owner);
        require(_to != address(0));
        _transfer(_from, _to, id);
    }

    /// @notice Change or reaffirm the approved address for an NFT
    /// @dev The zero address indicates there is no approved address.
    ///  Throws unless `msg.sender` is the current NFT owner, or an authorized
    ///  operator of the current owner.
    /// @param _approved The new approved NFT controller
    /// @param id The NFT to approve
    function approve(address _approved, uint256 id) external payable owns(id) {
        registrations[id].approval = _approved;
    }

    /// @notice Enable or disable approval for a third party ("operator") to manage
    ///  all of `msg.sender`'s assets
    /// @dev Emits the ApprovalForAll event. The contract MUST allow
    ///  multiple operators per owner.
    /// @param _operator Address to add to the set of authorized operators
    /// @param _approved True if the operator is approved, false to revoke approval
    function setApprovalForAll(address _operator, bool _approved) external {
        operators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    /// @notice Get the approved address for a single NFT
    /// @dev Throws if `id` is not a valid NFT.
    /// @param id The NFT to find the approved address for
    /// @return The approved address for this NFT, or the zero address if there is none
    function getApproved(uint256 id) external view returns (address) {
        require(ownerOf(id) != address(0));
        return registrations[id].approval;
    }

    /// @notice Query if an address is an authorized operator for another address
    /// @param _owner The address that owns the NFTs
    /// @param _operator The address that acts on behalf of the owner
    /// @return True if `_operator` is an approved operator for `_owner`, false otherwise
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return operators[_owner][_operator];
    }

    /// @notice Query if a contract implements an interface
    /// @param interfaceID The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function
    ///  uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceID` and
    ///  `interfaceID` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
        return interfaceID == 0x80ac58cd; // ERC721
    }

    function isContract(address addr) private view returns(bool) {
        uint size;
        assembly  {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    /**
     * @dev Transfer ownership of a name to another account.
     */
    function _transfer(address currentOwner, address newOwner, uint256 id) internal {
        ownershipCount[registrations[id].owner] -= 1;
        ownershipCount[newOwner] += 1;

        if(currentOwner != registrations[id].owner) {
            emit Transfer(registrations[id].owner, currentOwner, id);
        }
        emit Transfer(currentOwner, newOwner, id);

        registrations[id].owner = newOwner;
        registrations[id].approval = address(0);
    }
}
