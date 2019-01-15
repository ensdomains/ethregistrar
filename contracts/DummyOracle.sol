pragma solidity >=0.4.24;

contract DummyOracle {
    uint value;

    constructor(uint _value) {
        set(_value);
    }

    function set(uint _value) {
        value = _value;
    }

    function read() view returns (bytes32) {
        return bytes32(value);
    }
}
