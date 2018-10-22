pragma solidity ^0.4.20;

import "./PriceOracle.sol";
import "@ensdomains/ens/contracts/ENS.sol";
import "@ensdomains/ens/contracts/Deed.sol";
import "@ensdomains/ens/contracts/HashRegistrarSimplified.sol";
import "./BaseRegistrar.sol";

contract ETHRegistrar is BaseRegistrar {
    uint constant public INITIAL_RENEWAL_DURATION = 365 days;
    uint constant public TRANSFER_PERIOD = 90 days;

    Registrar public previousRegistrar;
    uint public transferCost;

    event NameMigrated(bytes32 indexed hash, address indexed owner, uint expires);

    constructor(ENS _ens, bytes32 _baseNode, PriceOracle _prices, Registrar prev, uint _transferCost) BaseRegistrar(_ens, _baseNode, _prices) public {
        previousRegistrar = prev;
        transferCost = _transferCost;
    }

    /**
     * @dev Transfers a registration from the initial registrar.
     * This function is called by the initial registrar when a user calls `transferRegistrars`.
     */
    function acceptRegistrarTransfer(bytes32 hash, Deed deed, uint) external {
        require(msg.sender == address(previousRegistrar));
        require(registrations[hash].owner == address(0));

        address owner = deed.owner();

        // Compute the duration and renewal fee for the initial renewal.
        uint cost = transferCost;
        uint balance = address(deed).balance;
        if(cost > balance) {
            // If a year's rent is more than the deposit, give them a discount.
            cost = balance;
        }

        // Destroy the deed and transfer the funds here.
        deed.setOwner(this);
        deed.closeDeed(1000);

        // Register the name
        doRegister(hash, owner, INITIAL_RENEWAL_DURATION);
        emit NameMigrated(hash, owner, now + INITIAL_RENEWAL_DURATION);

        // Transfer excess funds back to the domain owner.
        owner.transfer(balance - cost);
    }

    function available(string name) public view returns(bool) {
        return super.available(name) && (now > deployedAt + TRANSFER_PERIOD || previousRegistrar.state(keccak256(name)) == Registrar.Mode.Open);
    }

    // Required so that deeds can be paid out
    function() public payable { }
}
