// Where artoo keeps what it records. Run logs hold screenshots and conversation logs hold
// whatever was asked and answered, so they live under XDG data -- never inside the dotfiles
// repo, which is pushed to GitHub.
import { homedir } from "node:os";
import { join } from "node:path";

export const dataDir = () => join(process.env.XDG_DATA_HOME ?? join(homedir(), ".local", "share"), "artoo");
