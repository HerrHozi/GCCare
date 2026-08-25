import os
import csv
from datetime import datetime
from fit_tool.fit_file_builder import FitFileBuilder
from fit_tool.profile.messages.file_id_message import FileIdMessage
from fit_tool.profile.messages.weight_scale_message import WeightScaleMessage
from fit_tool.profile.profile_type import Manufacturer, FileType

#fit_tool-0.9.13.dist-info
# cd "C:\Users\HolgerZimmermann\OneDrive - mrhozi\#DailyBuild\GarminConnect\RD545"

INPUT_CSV = r"C:\Users\HolgerZimmermann\OneDrive - mrhozi\#DailyBuild\GarminConnect\RD545\bodydata.csv"  # Pfad zur neuen CSV-Datei
OUTPUT_DIR = r"C:\Users\HolgerZimmermann\OneDrive - mrhozi\#DailyBuild\GarminConnect\RD545\generated_fits"
HEIGHT_CM = 178.0

os.makedirs(OUTPUT_DIR, exist_ok=True)
height_m = HEIGHT_CM / 100

last_x = int(input("Wie viele der letzten Einträge sollen exportiert werden? "))

with open(INPUT_CSV, newline='', encoding='utf-8') as csvfile:
    reader = csv.DictReader(csvfile)
    rows = list(reader)

rows = rows[-last_x:]

for row in rows:
    timestamp = datetime.strptime(row["Date"], "%Y-%m-%d %H:%M:%S")
    timestamp_ms = round(timestamp.timestamp() * 1000)

    weight = float(row["Weight (kg)"])
    fat_percent = float(row["Body Fat (%)"])
    hydration = float(row["Body Water (%)"])
    muscle_mass = float(row["Muscle Mass (kg)"])
    bone_mass = float(row["Bone Mass (kg)"])
    age = int(float(row["Metab Age"]))
    bmi = float(row["BMI"])
    visceral_fat = int(float(row["Visc Fat"]))
    fat_mass = round(weight * (fat_percent / 100.0), 2)
    physique_rating = int(float(row["Physique Rating"]))

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

    filename = f"{OUTPUT_DIR}/weight_{timestamp.strftime('%Y-%m-%d_%H-%M')}.fit"
    fit_file.to_file(filename)
    print(f"✅ FIT-Datei erzeugt: {filename}")
