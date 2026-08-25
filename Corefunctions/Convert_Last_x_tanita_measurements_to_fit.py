import argparse
import csv
import os
from datetime import datetime
from fit_tool.fit_file_builder import FitFileBuilder
from fit_tool.profile.messages.file_id_message import FileIdMessage
from fit_tool.profile.messages.weight_scale_message import WeightScaleMessage
from fit_tool.profile.profile_type import Manufacturer, FileType

def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert Tanita CSV measurements to Garmin FIT weight files."
    )
    parser.add_argument("--input-csv", required=True, help="Path to the Tanita CSV file.")
    parser.add_argument("--output-dir", required=True, help="Directory where FIT files will be written.")
    parser.add_argument(
        "--height-cm",
        required=True,
        type=float,
        help="Body height in centimeters. Used as BMI fallback when BMI is missing in the CSV.",
    )
    parser.add_argument(
        "--last-x",
        type=int,
        help="Number of latest CSV rows to export. If omitted, the script prompts for it.",
    )
    return parser


def get_last_x(value_from_args: int | None) -> int:
    if value_from_args is not None:
        if value_from_args <= 0:
            raise ValueError("--last-x must be greater than zero.")
        return value_from_args

    prompted_value = int(input("How many of the latest entries should be exported? "))
    if prompted_value <= 0:
        raise ValueError("The number of entries must be greater than 0.")

    return prompted_value


def get_float(row: dict[str, str], column_name: str) -> float:
    return float(row[column_name])


def main() -> int:
    args = build_argument_parser().parse_args()

    input_csv = os.path.abspath(args.input_csv)
    output_dir = os.path.abspath(args.output_dir)
    height_cm = args.height_cm
    height_m = height_cm / 100.0
    last_x = get_last_x(args.last_x)

    if not os.path.isfile(input_csv):
        raise FileNotFoundError(f"CSV file not found: {input_csv}")

    if height_cm <= 0:
        raise ValueError("--height-cm must be greater than zero.")

    os.makedirs(output_dir, exist_ok=True)

    with open(input_csv, newline="", encoding="utf-8") as csvfile:
        reader = csv.DictReader(csvfile)
        rows = list(reader)

    rows = rows[-last_x:]

    for row in rows:
        timestamp = datetime.strptime(row["Date"], "%Y-%m-%d %H:%M:%S")
        timestamp_ms = round(timestamp.timestamp() * 1000)

        weight = get_float(row, "Weight (kg)")
        fat_percent = get_float(row, "Body Fat (%)")
        fat_mass = round(weight * (fat_percent / 100.0), 2)
        hydration = get_float(row, "Body Water (%)")
        muscle_mass = get_float(row, "Muscle Mass (kg)")
        bone_mass = get_float(row, "Bone Mass (kg)")
        age = int(float(row["Metab Age"]))
        visceral_fat = int(float(row["Visc Fat"]))
        physique_rating = int(float(row["Physique Rating"]))

        bmi_value = row.get("BMI")
        if bmi_value in (None, ""):
            bmi = round(weight / (height_m * height_m), 2)
        else:
            bmi = float(bmi_value)

        file_id = FileIdMessage()
        file_id.type = FileType.WEIGHT
        file_id.manufacturer = Manufacturer.GARMIN
        file_id.time_created = timestamp_ms

        msg = WeightScaleMessage()
        msg.timestamp = timestamp_ms
        msg.weight = weight
        msg.percent_fat = fat_percent
        msg.percent_hydration = hydration
        msg.bone_mass = fat_mass
        msg.muscle_mass = muscle_mass
        msg.bmi = bmi
        msg.visceral_fat_rating = visceral_fat
        msg.metabolic_age = age
        msg.user_profile_index = 0
        msg.basal_met = 2000
        msg.active_met = 2000
        msg.physique_rating = physique_rating

        builder = FitFileBuilder(auto_define=True)
        builder.add(file_id)
        builder.add(msg)
        fit_file = builder.build()

        filename = os.path.join(output_dir, f"weight_{timestamp.strftime('%Y-%m-%d_%H-%M')}.fit")
        fit_file.to_file(filename)
        print(f"FIT file created: {filename}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
