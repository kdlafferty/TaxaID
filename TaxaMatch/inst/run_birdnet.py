from birdnetlib import Recording
from birdnetlib.analyzer import Analyzer
import os, csv

audio_dir  = "TaxaLikely/reference_audio/song/"
result_dir = "TaxaLikely/birdnet_results/song/"
os.makedirs(result_dir, exist_ok=True)

analyzer = Analyzer()
files = [f for f in os.listdir(audio_dir)
         if f.lower().endswith((".mp3", ".wav", ".flac", ".ogg"))]
print(f"Processing {len(files)} files...")
for i, fname in enumerate(files, 1):
    print(f"  [{i}/{len(files)}] {fname}")
    rec = Recording(analyzer, os.path.join(audio_dir, fname),
                    lat=37.5, lon=-122.0, min_conf=0.0)
    rec.analyze()
    out = os.path.join(result_dir,
                       os.path.splitext(fname)[0] + '.BirdNET.results.csv')
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Start (s)", "End (s)", "Scientific name",
                    "Common name", "Confidence"])
        for d in rec.detections:
            w.writerow([d["start_time"], d["end_time"],
                        d["scientific_name"], d["common_name"],
                        d["confidence"]])
print("Done.")
