# Platform9 Log File Uploader

A lightweight, dependency-free Bash script for securely uploading files to a Platform9 bucket using presigned URLs.  
The script automatically identifies your customer prefix, generates an upload key, requests a presigned URL, and performs the upload — all in one command.

---

## 📋 Table of Contents
- [Introduction](#introduction)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Error Handling](#error-handling)
- [Troubleshooting](#troubleshooting)
- [Author](#author)

---

## 🧭 Introduction

The `pf9_upload.sh` script simplifies the process of uploading files to an S3-compatible endpoint using Platform9’s upload API.  
It validates the provided upload token, identifies the appropriate bucket and prefix, and securely uploads the file with server-side encryption.

This tool is ideal for environments where automation, simplicity, and portability are key.

---

## 🚀 Features
- ✅ No dependencies beyond **Bash** and **curl** (works on Linux/macOS)
- 🔐 Secure upload via short-lived (900 sec) **presigned S3 PUT URLs**
- 🧾 Automatic prefix and bucket detection via `/whoami` API
- 💾 File size validation (up to **5 GiB**)
- 📊 Helpful, color-coded terminal output
- 🧠 Graceful error handling with debug information

---

## ⚙️ Requirements
- `bash`
- `curl`
- `stat` (available by default on most Unix systems)
- Internet access to the specified API endpoint

> 📝 **Note:** No Python or `jq` dependencies required.

---

## 💡 Installation

Clone this repository or download the script directly:

```bash
git clone https://github.com/platform9/log-uploads.git
cd log-uploads
chmod +x pf9_upload.sh
```
Or download directly:
```bash
curl -O https://raw.githubusercontent.com/platform9/log-uploads/pf9_upload.sh
chmod +x pf9_upload.sh
```

---

## 🧰 Usage
```bash
./pf9_upload.sh <TOKEN> <TICKET> <FILE>
```
| Argument   | Description                               |
| ---------- | ----------------------------------------- |
| `<TOKEN>`  | Upload token provided by Platform9        |
| `<TICKET>` | Unique identifier for this upload session |
| `<FILE>`   | Local path to the file you want to upload |

---

## ⚠️ Error Handling

The script provides descriptive error messages when:

- Token is invalid or not authorized
- File is too large or missing
- API endpoints are misconfigured or unreachable
- Presign URL is missing or invalid.

All failures print helpful debug output to assist troubleshooting.

---

## 🧯 Troubleshooting
| Problem                       | Possible Cause                  | Solution                         |
| ----------------------------- | ------------------------------- | -------------------------------- |
| `whoami request failed`       | Network issue or wrong API base | Check `API_BASE` or connectivity |
| `file too large`              | File exceeds 5 GiB              | Split file or reduce size        |
| `Presign API returned error`  | Token not authorized or expired | Regenerate token                 |
| `Upload failed with HTTP 403` | Presigned URL expired           | Retry the upload                 |


---

## 🧩 Author
Developed by Platform9 Systems
Maintained by the Platform9 SRE team.
