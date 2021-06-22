// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0 <0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Whitelist.sol";

interface ITokenStake {
    function updateIndex() external;
}

contract Esm is Whitelist {
    /// @notice Access stake pause
    uint256 public stakeLive = 1;
    /// @notice Access redeem pause
    uint256 public redeemLive = 1;
    /// @notice System closed time
    uint256 public time;
    /// @notice TokenStake for updating on closed
    ITokenStake public tokenStake;

    /// @notice System closed yet event
    event ShutDown(uint256 blocknumber, uint256 time);

    /**
     * @notice Construct a new Esm
     */
    constructor() public {}


    /**
     * @notice Set with tokenStake
     * @param _tokenStake Address of tokenStake
     */
    function setupTokenStake(address _tokenStake) public onlyWhitelisted {
        tokenStake = ITokenStake(_tokenStake);
    }

    /**
     * @notice Open stake, if stake pasued
     */
    function openStake() external onlyWhitelisted {
        stakeLive = 1;
    }

    /**
     * @notice Paused stake, if stake opened
     */
    function pauseStake() external onlyWhitelisted {
        stakeLive = 0;
    }

    /**
     * @notice Open redeem, if redeem paused
     */
    function openRedeem() external onlyWhitelisted {
        redeemLive = 1;
    }

    /**
     * @notice Pause redeem, if redeem opened
     */
    function pauseRedeem() external onlyWhitelisted {
        redeemLive = 0;
    }

    /**
     * @notice Status of staking
     */
    function isStakePaused() external view returns (bool) {
        return stakeLive == 0;
    }

    /**
     * @notice Status of redeem
     */
    function isRedeemPaused() external view returns (bool) {
        return redeemLive == 0;
    }

    /**
     * @notice Status of closing-sys
     */
    function isClosed() external view returns (bool) {
        return time > 0;
    }

    /**
     * @notice If anything error, project manager can shutdown it
     *         anybody cant stake, but can redeem
     */
    function shutdown() external onlyWhitelisted {
        require(time == 0, "System closed yet.");
        tokenStake.updateIndex();
        time = block.timestamp;
        emit ShutDown(block.number, time);
    }
}
