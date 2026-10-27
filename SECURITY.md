# Security / 安全说明

## Do not commit（请勿提交）

Never commit secrets or personal environment data to this repository:

- API keys, tokens, passwords, cookies
- Claude / Anthropic account archives or session files
- Clash / proxy **subscription URLs**, node names, or provider credentials
- Local absolute paths unique to one machine (e.g. a personal user folder or a personal drive path)
- Real public IPs, home broadband identifiers, or payment details

## Safe defaults

- `guard-settings.json` in this tree uses `auto: true` with empty country fields.
- Install packages must be scrubbed before sharing.
- Releases (when published) should contain only the clean installer, not personal backups.

## Reporting

If you find accidental secrets in history or a release artifact, open an issue (without pasting the secret) so the owner can rotate and purge.
