pragma solidity ^0.4.20;

import "@ensdomains/ens/contracts/ENS.sol";
import "@ensdomains/ens/contracts/Deed.sol";
import "@ensdomains/ens/contracts/HashRegistrarSimplified.sol";
import "./BaseRegistrar.sol";

contract ETHRegistrar is BaseRegistrar {
    uint constant INITIAL_RENEWAL_DURATION = 365 days;
    uint constant TRANSFER_PERIOD = 90 days;

    Registrar public previousRegistrar;

    constructor(ENS _ens, bytes32 _baseNode, Registrar prev) BaseRegistrar(_ens, _baseNode) public {
        previousRegistrar = prev;
    }

    /**
     * @dev Transfers a registration from the initial registrar.
     * This function is called by the initial registrar when a user calls `transferRegistrars`.
     */
    function acceptRegistrarTransfer(bytes32 hash, Deed deed, uint) external {
        require(msg.sender == address(previousRegistrar));
        require(registrations[hash].owner == address(0));

        // Compute the duration and renewal fee for the initial renewal.
        uint cost = rentPrice(hash, INITIAL_RENEWAL_DURATION);
        uint balance = address(deed).balance;
        if(cost > balance) {
            // If a year's rent is more than the deposit, give them a discount.
            cost = balance;
        }

        // Destroy the deed and transfer the funds here.
        deed.setOwner(this);
        deed.closeDeed(1000);

        // Transfer excess funds back to the domain owner.
        address owner = deed.owner();
        owner.transfer(balance - cost);

        // Register the name
        doRegister(hash, owner, INITIAL_RENEWAL_DURATION);
    }

    function available(bytes32 hash) public view returns(bool) {
        return super.available(hash) && previousRegistrar.state(hash) == Registrar.Mode.Open;
    }

    // Required so that deeds can be paid out
    function() public payable { }
}
