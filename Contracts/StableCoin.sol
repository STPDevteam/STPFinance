// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Pausable.sol";
import "./Whitelist.sol";


contract StableCoin is ERC20Pausable, Whitelist {


    constructor(string memory name, string memory symbol, uint8 decimals) 
    ERC20(name, symbol) 
    public {
        _setupDecimals(decimals);
    }

    function mint(address account, uint256 amount) public onlyWhitelisted{
        _mint(account, amount);
    }


    function burn(address account, uint256 amount) public onlyWhitelisted{
        _burn(account, amount);
    }

    function pause() external onlyWhitelisted{
        _pause();
    }

    function unpause() external onlyWhitelisted{
        _unpause();
    }
}
