// Asking the human. Terminal only for now; a notify-send / Quickshell prompt comes later.
export type Confirm = (message: string) => Promise<boolean>;

export const ttyConfirm: Confirm = async (message) => {
  // No terminal to ask on means no consent.
  if (!process.stdin.isTTY) return false;
  const answer = prompt(`${message} [y/N]`);
  return /^y(es)?$/i.test(answer?.trim() ?? "");
};
