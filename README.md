# Hindi & Urdu Speech-to-Text (Whisper)

A ready-to-run notebook that transcribes **Hindi** and **Urdu** audio into text —
the audio equivalent of what Whisper does for English.

**Notebook:** [`Hindi_Urdu_Audio_Model.ipynb`](./Hindi_Urdu_Audio_Model.ipynb)

## The idea in one line
OpenAI's **Whisper is already multilingual** — the same model that transcribes English
natively supports Hindi (`hi`) and Urdu (`ur`), among ~99 languages. You don't install a
different architecture; you just tell it which language to listen for. For the best
accuracy on these two languages specifically, the notebook also shows drop-in
**fine-tuned** checkpoints.

## What's inside
| # | Approach | Model | Best for |
|---|----------|-------|----------|
| 1 | OpenAI Whisper (`whisper` package) | `whisper` tiny→large-v3 | Quick start — one line to transcribe |
| 2 | Whisper via 🤗 Transformers | `openai/whisper-large-v3` | Long audio, timestamps, pipelines |
| 3 | Fine-tuned Hindi/Urdu models | `vasista22/whisper-hindi-large-v2`, `kingabzpro/whisper-large-v3-urdu` | Highest accuracy on Hindi/Urdu |

The notebook also generates its own sample Hindi/Urdu clips (via text-to-speech) so it
runs end-to-end with no audio file to prepare, plus a reusable
`hindi_urdu_transcribe(...)` helper you can copy into your own project.

## How to run
- **Google Colab (recommended):** open the notebook, set *Runtime → Change runtime type → GPU*,
  then run all cells. A GPU makes `medium`/`large-v3` real-time; on CPU, stick to `small`.
- **Locally:** you need `ffmpeg` installed, then:
  ```bash
  pip install openai-whisper transformers accelerate gTTS
  ```

## Quick example
```python
import whisper
model = whisper.load_model("small")           # use "large-v3" on a GPU for best results
text = model.transcribe("audio.mp3", language="ur")["text"]   # "hi" for Hindi, "ur" for Urdu
print(text)
```

> Output is in the native script (Devanagari for Hindi, Nastaʿlīq for Urdu). Use
> `task="translate"` to get English instead. Accuracy is measured by **WER** (Word Error
> Rate) — lower is better, and bigger models score lower.
