"""Regenerate the original electronic bed (requires numpy). No external samples."""
from pathlib import Path
import numpy as np
import wave
OUT=Path(__file__).resolve().parents[1]/'functions/instagram_assets'
DURATION=90

def soundtrack():
    sr=44100
    t=np.arange(sr*DURATION)/sr
    audio=np.zeros_like(t)
    # Original low-key electronic bed. No external music or licensed samples.
    for beat in np.arange(0,DURATION,.6):
        u=t-beat
        mask=(u>=0)&(u<.24)
        audio[mask]+=.13*np.sin(2*np.pi*(54*u[mask]+2*(1-np.exp(-u[mask]*30))))*np.exp(-u[mask]*22)
    for i,start in enumerate(np.arange(0,DURATION,.3)):
        u=t-start; mask=(u>=0)&(u<.48)
        f=[261.63,329.63,392,493.88,392,329.63,293.66,392][i%8]
        audio[mask]+=.024*(np.sin(2*np.pi*f*u[mask])+.3*np.sin(2*np.pi*f*2*u[mask]))*np.exp(-u[mask]*9)*np.minimum(u[mask]*150,1)
    audio*=np.minimum(t/1.2,1)*np.minimum((DURATION-t)/1.4,1)
    stereo=np.stack((audio,audio),axis=1)
    with wave.open(str(OUT/'reel-bed.wav'),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr)
        f.writeframes((stereo*32767).astype('<i2').tobytes())


if __name__=='__main__':
    soundtrack()
