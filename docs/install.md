# Installing Flipper

## Before you start

You need:

- **World of Warcraft: Forever**, installed through Battle.net.
- **Auctionator.** Flipper gets its prices from it and adds its AH tab through a library Auctionator ships. Without it, Flipper only works if TSM is installed, and has no AH tab.

Optional:

| Addon | Adds |
|---|---|
| Questie | Vendor names and map positions for items you haven't bought yet |
| Journalator | Your own sold and unsold counts in the tooltip |
| TSM | Used for prices instead of Auctionator when present |

## Find your AddOns folder

Forever has its own folder, separate from retail and Classic:

```
<Battle.net games folder>\World of Warcraft\_forever_\Interface\AddOns
```

On a default install that is `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`. If you're not sure, open the Battle.net app, select World of Warcraft, pick the Forever version, then **Options (gear) > Show in Explorer**, and go into `Interface\AddOns`. Create `AddOns` if it doesn't exist.

## Install from a release

1. Download `Flipper-<version>.zip` from the [Releases page](https://github.com/glholland/Flipper/releases).
2. Unzip it into the AddOns folder. The zip already contains a `Flipper` folder, so the result must be:

   ```
   AddOns\
     Flipper\
       Flipper.toc
       Core\
       Data\
       UI\
   ```

   Not `AddOns\Flipper-0.2.0\Flipper\Flipper.toc`. If Windows created an extra folder named after the zip, move the inner `Flipper` folder up one level.
3. If the game is running, exit it completely. `/reload` does not load an addon the game didn't know about at startup.
4. Start the game. On the character select screen, click **AddOns** (bottom left) and check that **Flipper** is ticked.

## Check it works

1. Log in and type `/flip`. The Flipper window should open.
2. Open the auction house. A **Flipper** tab appears along the bottom, next to Auctionator's tabs.
3. Hover any item. The tooltip should have a green "Flipper" line once Auctionator has prices.

Then follow [First steps](../README.md#first-steps) to give Flipper prices and recipes to work with.

## Updating

1. Exit the game.
2. Delete the old `AddOns\Flipper` folder. Your settings, vendor memory and sales history are kept: they live in `WTF\Account\<account>\SavedVariables\Flipper.lua`, not in the addon folder.
3. Unzip the new release as above and start the game.

## Uninstalling

Delete `AddOns\Flipper`. To also remove its saved data, delete `Flipper.lua` from `WTF\Account\<account>\SavedVariables\` and from each character's `SavedVariables` folder under `WTF\Account\<account>\<realm>\<character>\`.

## Install from source

For working on Flipper, link the repository's `Flipper` folder into AddOns instead of copying it, so the game always runs your working copy.

```bash
git clone https://github.com/glholland/Flipper.git
```

Then, in a Command Prompt (paths adjusted to yours):

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Flipper" "C:\path\to\Flipper\Flipper"
```

A junction (`/J`) needs no administrator rights. Edits to existing files load with `/reload`; new files need a full restart. See [Development](development.md) for tests and CI.

## Install problems

**Flipper isn't in the AddOns list.** The folder is in the wrong place or nested one level too deep. `Flipper.toc` must sit directly inside `AddOns\Flipper\`.

**Flipper is listed as "Incompatible" or "Out of date".** Tick **Load out of date AddOns** at the top of the AddOns list. This happens when a game patch raises the interface version before a new Flipper release.

**`/flip` does nothing.** The game was not restarted after installing, or Flipper is unticked for this character.

**No Flipper tab at the auction house.** Auctionator is missing or disabled. `/flip` still opens the window.

More in [Troubleshooting](troubleshooting.md).
