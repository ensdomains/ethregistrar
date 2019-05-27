pragma solidity ^0.5.0;

import "@ensdomains/dnssec-oracle/contracts/DNSSEC.sol";
import "@ensdomains/dnssec-oracle/contracts/BytesUtils.sol";
import "@ensdomains/dnsregistrar/contracts/DNSClaimChecker.sol";
import "@ensdomains/buffer/contracts/Buffer.sol";
import "./BaseRegistrar.sol";
import "./StringUtils.sol";
import "./PriceOracle.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * @dev ShortNameClaims is a contract that permits people to register claims
 *      for short (3-6 character) ENS names ahead of the auction process.
 *
 *      Anyone with a DNS name registered before January 1, 2019, may use this
 *      name to support a claim for a matching ENS name. In the event that
 *      multiple claimants request the same name, the name will be assigned to
 *      the oldest registered DNS name.
 *
 *      Claims may be submitted by calling `submitExactClaim`,
 *      `submitCombinedClaim` or `submitPrefixClaim` as appropriate.
 *
 *      Claims require lodging a deposit equivalent to 365 days' registration of
 *      the name. If the claim is approved, this deposit is spent, and the name
 *      is registered for the claimant for 365 days. If the claim is declined,
 *      the deposit will be returned.
 */
contract ShortNameClaims is Ownable {
    uint constant public REGISTRATION_PERIOD = 31536000;

    using StringUtils for string;
    using BytesUtils for bytes;
    using Buffer for Buffer.buffer;

    struct Claim {
        bytes32 labelHash;
        address claimant;
        uint paid;
    }

    DNSSEC public oracle;
    PriceOracle public priceOracle;
    BaseRegistrar public registrar;
    mapping(bytes32=>Claim) public claims;
    uint public claimCount;

    event ClaimSubmitted(string claimed, bytes dnsname, uint paid);
    event ClaimApproved(bytes32 indexed claimId);
    event ClaimDeclined(bytes32 indexed claimId);

    constructor(DNSSEC _oracle, PriceOracle _priceOracle, BaseRegistrar _registrar) public {
        oracle = _oracle;
        priceOracle = _priceOracle;
        registrar = _registrar;
    }

    /**
     * @dev Computes the claim ID for a submitted claim, so it can be looked up
     *      using `claims`.
     * @param claimed The name being claimed (eg, 'foo')
     * @param dnsname The DNS-encoded name supporting the claim (eg, 'foo.test')
     * @return The claim ID.
     */
    function computeClaimId(string memory claimed, bytes memory dnsname) public pure returns(bytes32) {
        return keccak256(abi.encodePacked(claimed, dnsname));
    }

    /**
     * @dev Returns the cost associated with placing a claim.
     * @param claimed The name being claimed.
     * @return The cost in wei for this claim.
     */
    function getClaimCost(string memory claimed) public view returns(uint) {
        return priceOracle.price(claimed, 0, REGISTRATION_PERIOD);
    }

    /**
     * @dev Submits a claim for an exact match (eg, foo.test -> foo.eth).
     *      Claimants must provide an amount of ether equal to 365 days'
     *      registration cost; call `getClaimCost` to determine this amount.
     *      Claimants should supply a little extra in case of variation in price;
     *      any excess will be returned to the sender.
     * @param name The DNS-encoded name of the domain being used to support the
     *             claim.
     * @param input Zero or more DNSSEC-signed RRSETs, in the format expected by
     *              the DNSSEC oracle (https://github.com/ensdomains/dnssec-oracle/blob/0577b077a2e5454b4eb120cba595c69cf214b3b9/contracts/DNSSECImpl.sol#L129).
     *              To be valid, the first entry must build off `proof`, and
     *              the last entry must be a TXT record on `'_ens.' + name`.
     *              If `input` is the empty string, `proof` is assumed to be the
     *              required TXT record, and already known to the oracle.
     * @param proof An RRSET already known to the DNSSEC oracle. If `input` is
     *              supplied, this RRSET must validate the first entry of `input`.
     *              If `input` is not supplied, this RRSET must be a TXT record
     *              known to the oracle on `'_ens.' + name`, in the format
     *              `a=0x...`.
     */
    function submitExactClaim(bytes memory name, bytes memory input, bytes memory proof) public payable {
        string memory claimed = getLabel(name, 0);
        handleClaim(claimed, name, input, proof);
    }

    /**
     * @dev Submits a claim for an exact match (eg, foo.tv -> footv).
     *      Claimants must provide an amount of ether equal to 365 days'
     *      registration cost; call `getClaimCost` to determine this amount.
     *      Claimants should supply a little extra in case of variation in price;
     *      any excess will be returned to the sender.
     * @param name The DNS-encoded name of the domain being used to support the
     *             claim.
     * @param input Zero or more DNSSEC-signed RRSETs, in the format expected by
     *              the DNSSEC oracle (https://github.com/ensdomains/dnssec-oracle/blob/0577b077a2e5454b4eb120cba595c69cf214b3b9/contracts/DNSSECImpl.sol#L129).
     *              To be valid, the first entry must build off `proof`, and
     *              the last entry must be a TXT record on `'_ens.' + name`.
     *              If `input` is the empty string, `proof` is assumed to be the
     *              required TXT record, and already known to the oracle.
     * @param proof An RRSET already known to the DNSSEC oracle. If `input` is
     *              supplied, this RRSET must validate the first entry of `input`.
     *              If `input` is not supplied, this RRSET must be a TXT record
     *              known to the oracle on `'_ens.' + name`, in the format
     *              `a=0x...`.
     */
    function submitCombinedClaim(bytes memory name, bytes memory input, bytes memory proof) public payable {
        bytes memory firstLabel = bytes(getLabel(name, 0));
        bytes memory secondLabel = bytes(getLabel(name, 1));
        Buffer.buffer memory buf;
        buf.init(firstLabel.length + secondLabel.length);
        buf.append(firstLabel);
        buf.append(secondLabel);

        handleClaim(string(buf.buf), name, input, proof);
    }

    /**
     * @dev Submits a claim for an exact match (eg, fooeth.test -> foo.eth).
     *      Claimants must provide an amount of ether equal to 365 days'
     *      registration cost; call `getClaimCost` to determine this amount.
     *      Claimants should supply a little extra in case of variation in price;
     *      any excess will be returned to the sender.
     * @param name The DNS-encoded name of the domain being used to support the
     *             claim.
     * @param input Zero or more DNSSEC-signed RRSETs, in the format expected by
     *              the DNSSEC oracle (https://github.com/ensdomains/dnssec-oracle/blob/0577b077a2e5454b4eb120cba595c69cf214b3b9/contracts/DNSSECImpl.sol#L129).
     *              To be valid, the first entry must build off `proof`, and
     *              the last entry must be a TXT record on `'_ens.' + name`.
     *              If `input` is the empty string, `proof` is assumed to be the
     *              required TXT record, and already known to the oracle.
     * @param proof An RRSET already known to the DNSSEC oracle. If `input` is
     *              supplied, this RRSET must validate the first entry of `input`.
     *              If `input` is not supplied, this RRSET must be a TXT record
     *              known to the oracle on `'_ens.' + name`, in the format
     *              `a=0x...`.
     */
    function submitPrefixClaim(bytes memory name, bytes memory input, bytes memory proof) public payable {
        bytes memory firstLabel = bytes(getLabel(name, 0));
        require(firstLabel.equals(firstLabel.length - 3, bytes("eth")));
        handleClaim(string(firstLabel.substring(0, firstLabel.length - 3)), name, input, proof);
    }

    function approveClaim(bytes32 claimId) onlyOwner public {
        Claim memory claim = claims[claimId];
        require(claim.paid > 0, "Claim not found");

        claimCount--;
        delete claims[claimId];
        emit ClaimApproved(claimId);

        registrar.register(uint256(claim.labelHash), claim.claimant, REGISTRATION_PERIOD);
        address(uint160(registrar.owner())).transfer(claim.paid);
    }

    function declineClaim(bytes32 claimId) onlyOwner public {
        Claim memory claim = claims[claimId];
        require(claim.paid > 0, "Claim not found");

        claimCount--;
        delete claims[claimId];
        emit ClaimDeclined(claimId);

        address(uint160(claim.claimant)).transfer(claim.paid);
    }

    function handleClaim(string memory claimed, bytes memory name, bytes memory input, bytes memory proof) internal {
        uint len = claimed.strlen();
        require(len >= 3 && len <= 6);

        bytes32 claimId = computeClaimId(claimed, name);
        require(claims[claimId].paid == 0, "Claim already submitted");

        // Require that there are at most two labels (name.tld)
        require(bytes(getLabel(name, 2)).length == 0, "Name must be a 2LD");

        uint price = getClaimCost(claimed);
        require(msg.value >= price, "Insufficient funds for reservation");
        if(msg.value > price) {
            msg.sender.transfer(msg.value - price);
        }

        if(input.length > 0) {
          proof = oracle.submitRRSets(input, proof);
        }

        (address addr, bool found) = DNSClaimChecker.getOwnerAddress(oracle, name, proof);
        require(found, "No DNS record found");

        claims[claimId] = Claim(keccak256(bytes(claimed)), addr, price);
        claimCount++;
        emit ClaimSubmitted(claimed, name, price);
    }

    function getLabel(bytes memory name, uint idx) internal pure returns(string memory) {
        // Skip the first `idx` labels
        uint offset = 0;
        for(uint i = 0; i < idx; i++) {
            if(offset >= name.length) return "";
            offset += name.readUint8(offset) + 1;
        }

        // Read the label we care about
        if(offset >= name.length) return '';
        uint len = name.readUint8(offset);
        return string(name.substring(offset + 1, len));
    }
}
