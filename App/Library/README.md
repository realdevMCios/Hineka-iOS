# Local mod and resource-pack library

- .jar mods and .zip resource packs are copied into Hineka's private app container.
- Imports must be regular, non-empty files with the expected extension, a ZIP/JAR signature, and a size no greater than 250 MiB.
- Hineka verifies the copied file again before adding it to the local manifest.
- Manifest filenames are restricted to generated UUID-based names and are checked before files are loaded or deleted. Missing, symbolic-link, size-mismatched, and unsafe-path entries are ignored.
- Enable/disable flags are profile metadata only. Files are not extracted, executed, installed into Minecraft, or activated by the current build.

Only import files from sources you trust. A ZIP signature is not a malware scan or a guarantee that an archive is structurally safe. Before archives are ever extracted or mods are executed, add bounded decompression, path-traversal checks for archive entries, compatibility validation, and a security review.

The online mod catalogue remains demo metadata. No hosted files are downloaded or installed; review author permission, redistribution licences, security, and compatibility before publishing real catalogue entries.
