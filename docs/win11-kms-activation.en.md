# Windows 11 Activation and Organization KMS Client Configuration

[中文](win11-kms-activation.md)

This project does not deploy, recommend, or provide third-party KMS emulators or public KMS addresses. Windows must be activated under licenses and terms that the user or organization actually owns.

## 1. Select a Legitimate Activation Path

Choose the path that matches the actual entitlement:

- **Retail / OEM / digital license:** appropriate for an individually licensed device or a long-lived single VM.
- **MAK:** appropriate when an organization assigns a Multiple Activation Key under its volume agreement.
- **Organization KMS:** only for an organization with Microsoft Volume Licensing, a valid CSVLK/KMS Host Key, and the required activation threshold.
- **Evaluation:** appropriate for short-term testing under the duration and terms of Microsoft's evaluation release.

Microsoft documents that a KMS Host must be activated with the CSVLK obtained through the organization's volume agreement and that Windows clients must meet the KMS activation threshold:

- [KMS activation planning](https://learn.microsoft.com/windows-server/get-started/kms-activation-planning)
- [Create a KMS activation host](https://learn.microsoft.com/windows-server/get-started/kms-create-host)

## 2. Retail, MAK, or Digital License

If the system was previously pointed to a specific KMS Host, clear that configuration before entering a legitimately owned Retail or MAK key:

```cmd
slmgr /ckms
slmgr /ipk <your-legitimate-retail-or-mak-key>
slmgr /ato
slmgr /xpr
```

Windows 11 also provides the graphical path:

```text
Settings → System → Activation → Change product key
```

## 3. Connect to an Organization's Official KMS

Use this client configuration only when an organization administrator has provided a legally deployed internal KMS Host. `<organization-kms-host>` must not be replaced with an unknown public KMS address.

Open PowerShell or Command Prompt as Administrator:

```cmd
slmgr /ipk <official-gvlk-matching-the-installed-windows-edition>
slmgr /skms <organization-kms-host>:1688
slmgr /ato
slmgr /xpr
```

A GVLK puts Windows into KMS Client mode. It is not a license and does not replace the organization's volume entitlement. Use Microsoft's official list to select the GVLK that matches the installed Windows edition:

- [KMS client activation keys](https://learn.microsoft.com/windows-server/get-started/kms-client-activation-keys)

## 4. Inspect and Troubleshoot

```cmd
slmgr /dlv
slmgr /xpr
```

- `0xC004F074`: the KMS Host is unreachable, or the organization has not met the activation threshold; contact the organization administrator.
- `0xC004F050`: the product key does not match the installed Windows edition.
- To restore KMS auto-discovery, run `slmgr /ckms` to remove the manually configured Host.

Successful activation does not automatically prove that the software is properly licensed. License validity depends on the key, acquisition channel, device or user assignment, and the applicable terms.
