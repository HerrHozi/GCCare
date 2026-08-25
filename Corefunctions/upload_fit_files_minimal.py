#!/usr/bin/env python3
"""Minimal Garmin Connect FIT file uploader.

Logs in to Garmin Connect and uploads all .fit files from a configurable folder.

Usage:
    python upload_fit_files_minimal.py --folder Corefunctions/test_data
"""

import argparse
import contextlib
import os
import sys
from getpass import getpass
from pathlib import Path

from garminconnect import (
    Garmin,
    GarminConnectAuthenticationError,
    GarminConnectConnectionError,
    GarminConnectTooManyRequestsError,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Upload FIT files to Garmin Connect.")
    parser.add_argument(
        "--folder",
        default=".",
        help="Folder that contains the FIT files to upload.",
    )
    parser.add_argument(
        "--tokenstore",
        default=os.getenv("GARMINTOKENS", "~/.garminconnect"),
        help="Path to the Garmin token store.",
    )
    return parser


def init_api(tokenstore: str) -> Garmin | None:
    tokenstore_path = str(Path(tokenstore).expanduser())

    try:
        garmin = Garmin()
        garmin.login(tokenstore_path)
        print(f"Logged in using saved tokens: {tokenstore_path}")
        return garmin
    except GarminConnectTooManyRequestsError as err:
        print(f"Rate limit error: {err}")
        return None
    except (GarminConnectAuthenticationError, GarminConnectConnectionError):
        print("No valid stored tokens found. Please log in.")

    try:
        email = os.getenv("EMAIL") or os.getenv("GARMIN_EMAIL") or input("Email: ").strip()
        password = os.getenv("PASSWORD") or os.getenv("GARMIN_PASSWORD") or getpass("Password: ")

        garmin = Garmin(
            email=email,
            password=password,
            prompt_mfa=lambda: input("MFA code: ").strip(),
        )
        garmin.login(tokenstore_path)
        print(f"Login successful. Tokens saved to: {tokenstore_path}")
        return garmin
    except GarminConnectTooManyRequestsError as err:
        print(f"Rate limit error: {err}")
        return None
    except GarminConnectAuthenticationError as err:
        print(f"Authentication failed: {err}")
        return None
    except GarminConnectConnectionError as err:
        print(f"Connection error: {err}")
        return None


def upload_fit_files(api: Garmin, folder: Path) -> int:
    if not folder.exists() or not folder.is_dir():
        print(f"Folder not found: {folder}")
        return 1

    fit_files = sorted(folder.glob("*.fit"))
    if not fit_files:
        print(f"No .fit files found in: {folder}")
        return 1

    success_count = 0
    failure_count = 0

    for fit_file in fit_files:
        try:
            print(f"Uploading: {fit_file.name}")
            result = api.upload_activity(str(fit_file))
            if result:
                success_count += 1
                print(f"OK: {fit_file.name}")
            else:
                failure_count += 1
                print(f"Failed: {fit_file.name}")
        except Exception as err:
            failure_count += 1
            print(f"Failed: {fit_file.name} - {err}")

    print(
        f"Done. Uploaded {success_count} file(s), {failure_count} failed from {folder}"
    )
    return 0 if failure_count == 0 else 1


def main() -> int:
    args = build_parser().parse_args()
    folder = Path(args.folder).expanduser().resolve()

    api = init_api(args.tokenstore)
    if not api:
        return 1

    return upload_fit_files(api, folder)


if __name__ == "__main__":
    with contextlib.suppress(KeyboardInterrupt):
        raise SystemExit(main())