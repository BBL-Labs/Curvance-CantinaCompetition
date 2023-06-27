// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../libraries/ERC20.sol";
import "./BaseOFTV2.sol";

abstract contract OFTV2 is BaseOFTV2, ERC20 {
    uint256 internal immutable ld2sdRate;

    string private _name;

    string private _symbol;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 _sharedDecimals,
        address _lzEndpoint,
        ICentralRegistry _centralRegistry
    )
        BaseOFTV2(_sharedDecimals, _lzEndpoint, _centralRegistry)
    {
        _name = name_;
        _symbol = symbol_;
        uint8 decimals = decimals();
        require(
            _sharedDecimals <= decimals,
            "OFT: sharedDecimals must be <= decimals"
        );
        ld2sdRate = 10**(decimals - _sharedDecimals);
    }

    /// @dev Returns the name of the token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /************************************************************************
     * public functions
     ************************************************************************/
    function circulatingSupply()
        public
        view
        virtual
        override
        returns (uint256)
    {
        return totalSupply();
    }

    function token() public view virtual override returns (address) {
        return address(this);
    }

    /************************************************************************
     * internal functions
     ************************************************************************/
    function _debitFrom(
        address _from,
        uint16,
        bytes32,
        uint256 _amount
    ) internal virtual override returns (uint256) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _burn(_from, _amount);
        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint256 _amount
    ) internal virtual override returns (uint256) {
        _mint(_toAddress, _amount);
        return _amount;
    }

    function _transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual override returns (uint256) {
        address spender = _msgSender();
        // if transfer from this contract, no need to check allowance
        if (_from != address(this) && _from != spender)
            _spendAllowance(_from, spender, _amount);
        _transfer(_from, _to, _amount);
        return _amount;
    }

    function _ld2sdRate() internal view virtual override returns (uint256) {
        return ld2sdRate;
    }
}
