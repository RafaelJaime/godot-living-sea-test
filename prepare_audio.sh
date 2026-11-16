#!/bin/zsh
# Builds godot/assets/audio/*.ogg from the CC0 OpenGameArt packs listed in ATTRIBUTION.md (see odd/audio_plan_preview/PLAN.md).
#   AUDIO_SRC=<dir with vistula_short.mp3, beach_wave_0N.flac, windN.wav, gull_N.wav, gull_big1.wav, rumbling17.wav, craft_hammer.ogg, Loop_Minstrel_Dance_0.wav, ws/workshop (unzipped workshop.7z), x/ (unzipped sfx packs)> ./prepare_audio.sh
set -e
S=${AUDIO_SRC:?set AUDIO_SRC}
O=$(dirname $0)/godot/assets/audio
mkdir -p $O
enc() { ffmpeg -v error -y -i "$1" ${@:3} -f wav - | oggenc -Q -q $2 -o "$O/$3" - 2>/dev/null; }
# Sea bed: 90 s of the river/sea recording turned into a seamless loop (3 s equal-power crossfade of tail into head).
ffmpeg -v error -y -ss 30 -t 90 -i $S/vistula_short.mp3 -ac 2 -ar 44100 -filter_complex "[0:a]atrim=3:87,asetpts=PTS-STARTPTS[mid];[0:a]atrim=87:90,asetpts=PTS-STARTPTS[tail];[0:a]atrim=0:3,asetpts=PTS-STARTPTS[head];[tail][head]acrossfade=d=3:c1=qsin:c2=qsin[x];[mid][x]concat=n=2:v=0:a=1" -f wav - | oggenc -Q -q 2 -o $O/sea_loop.ogg -
for i in 1 2 3 4; do ffmpeg -v error -y -i $S/beach_wave_0$i.flac -ac 2 -ar 44100 -f wav - | oggenc -Q -q 3 -o $O/wave_$i.ogg -; done
for i in 1 2 3 4 5; do ffmpeg -v error -y -i $S/wind$i.wav -ac 1 -ar 32000 -f wav - | oggenc -Q -q 1 -o $O/wind_$i.ogg -; done
for i in 1 2 3 4 5 6 7; do ffmpeg -v error -y -i $S/gull_$i.wav -ac 1 -ar 44100 -f wav - | oggenc -Q -q 3 -o $O/gull_$i.ogg -; done
ffmpeg -v error -y -i $S/gull_big1.wav -ac 1 -ar 44100 -f wav - | oggenc -Q -q 3 -o $O/gull_8.ogg -
n=1; for f in $S/x/floor_creak1.wav $S/x/floor_creak2.wav $S/x/floor_creak3.wav $S/x/sfx100v2_wood_01.ogg $S/x/sfx100v2_wood_02.ogg $S/x/sfx100v2_wood_03.ogg $S/x/sfx100v2_wood_04.ogg; do
  ffmpeg -v error -y -i $f -ac 1 -ar 44100 -f wav - | oggenc -Q -q 3 -o $O/creak_$n.ogg -; n=$((n+1)); done
cp $S/x/rain.ogg $O/rain.ogg
cp $S/x/sfx100v2_thunder_01.ogg $O/thunder.ogg
ffmpeg -v error -y -ss 5 -t 40 -i $S/rumbling17.wav -ac 1 -ar 32000 -af "afade=t=in:d=2,afade=t=out:st=36:d=4" -f wav - | oggenc -Q -q 1 -o $O/rumble.ogg -
ffmpeg -v error -y -i $S/x/bell.wav -ac 1 -ar 44100 -f wav - | oggenc -Q -q 3 -o $O/bell.ogg -
# Crew hooks (Audio.footstep / Audio.play_at): wood and wet footsteps, hammer, saw-like scrape, a violin-tavern track (candidate, see PLAN).
for i in 1 2 3 4; do ffmpeg -v error -y -i $S/x/sfx100v2_footstep_wood_0$i.ogg -ac 1 -ar 44100 -f wav - | oggenc -Q -q 3 -o $O/step_wood_$i.ogg -; done
for i in 1 2 3; do ffmpeg -v error -y -i $S/x/sfx100v2_footstep_wet_0$i.ogg -ac 1 -ar 44100 -f wav - | oggenc -Q -q 3 -o $O/step_wet_$i.ogg -; done
cp $S/craft_hammer.ogg $O/hammer_hit.ogg
ffmpeg -v error -y -i "$S/ws/workshop/workshop - wood hammering.wav" -ac 1 -ar 44100 -f wav - | oggenc -Q -q 3 -o $O/hammer_loop.ogg -
ffmpeg -v error -y -i "$S/ws/workshop/workshop - quiet scrape.wav" -ac 1 -ar 44100 -f wav - | oggenc -Q -q 3 -o $O/saw_loop.ogg -
ffmpeg -v error -y -t 60 -i $S/Loop_Minstrel_Dance_0.wav -ac 2 -ar 44100 -f wav - | oggenc -Q -q 2 -o $O/violin_loop.ogg -
ls -la $O
