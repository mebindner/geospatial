#!/bin/zsh
# =============================================================================
# Render the video in batches, each in a fresh R process
# -----------------------------------------------------------------------------
# rgl does not release memory when a scene is rebuilt for every frame, so one
# long session grows to ~10 GB and slows to a crawl in swap. Running batches of
# frames in separate processes keeps memory flat. Frames already on disk are
# kept (resume), so the script can be re-run after an interruption.
#
# Usage (from the repository root):  zsh 06-widest-view/render_batches.sh
# =============================================================================

set -e
cd "$(dirname "$0")"
export DISPLAY=:0
BATCH=50
TOTAL=450

for start in $(seq 1 $BATCH $TOTAL); do
  end=$(( start + BATCH - 1 )); (( end > TOTAL )) && end=$TOTAL
  echo "Frames $start-$end"
  Rscript -e "
    invisible(Sys.setlocale('LC_CTYPE', 'en_US.UTF-8'))
    PROJECT <- '.'; for (f in list.files('R', pattern = '[.]R\$', full.names = TRUE)) source(f)
    terra::terraOptions(progress = 0); suppressMessages(library(sf))
    screen <- run_screening(); final <- run_final(run_ranking(screen)); refs <- run_references(screen)
    make_video <- local({ mv <- make_video; function(...) mv(..., only_frames = $start:$end, resume = TRUE) })
    source('video_story.R')
  " 2>&1 | grep -E "^frame|Error|CHECK" || true
done

# Encode the finished frames
ffmpeg -y -loglevel error -framerate 25 -i output/frames/f%04d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 18 output/widest_view.mp4
cp output/frames/f$(printf "%04d" $TOTAL).png output/widest_view_final.png
echo "Video: output/widest_view.mp4"
