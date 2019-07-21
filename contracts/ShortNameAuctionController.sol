pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./BaseRegistrar.sol";
import "./StringUtils.sol";

interface ProxyRegistry {
    function proxies(address owner) external view returns(address);
}

contract ShortNameAuctionController {
    using StringUtils for *;

    uint constant public REGISTRATION_PERIOD = 31536000;

    event NameRegistered(string name, address owner);

    BaseRegistrar public base;
    ProxyRegistry public proxies;
    address public opensea;

    modifier onlyOpensea {
        require(msg.sender == opensea || msg.sender == proxies.proxies(opensea));
        _;
    }

    constructor(BaseRegistrar _base, ProxyRegistry _proxies, address _opensea) public {
        base = _base;
        proxies = _proxies;
        opensea = _opensea;
    }

    function valid(string memory name) public view returns(bool) {
        uint len = name.strlen();
        return len >= 3 && len <= 6;
    }

    function available(string memory name) public view returns(bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function register(string calldata name, address owner) external onlyOpensea {
        require(available(name));
        base.register(uint256(keccak256(bytes(name))), owner, REGISTRATION_PERIOD);
        emit NameRegistered(name, owner);
    }
}
