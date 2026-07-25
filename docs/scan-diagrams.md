# Riva Scan — Diagrams

These diagrams live as **editable Mermaid** inside the code fences below. GitHub, VS Code
(with a Mermaid extension), Obsidian, and Notion all render them live — just edit the text
between the ` ```mermaid ` fences and the picture updates. The matching `.png` exports are
in this folder if you need a flat image.

---

## 1. How it works (plain language)

```mermaid
flowchart TD
    A["You snap your food<br/>(tap the center, then a slow 3-5s arc)"]:::you
    subgraph AUTO["Behind the scenes"]
        direction TB
        B["Your phone does preprocessing and converts video into images. It keeps only the clear, sharp shots"]:::auto
        C["It finds your food and separates it from the table"]:::auto
        D["It measures how much food is really there"]:::auto
        E["It figures out the ingredients<br/>(your note helps, like 'Chipotle bowl')"]:::auto
        F["It turns the size and ingredients into the numbers"]:::auto
        B --> C --> D --> E --> F
    end
    G["You see your result<br/>640 Calories · 45g protein · 62g carbs · 18g fat"]:::you
    A --> B
    F --> G

    classDef you fill:#dff0e8,stroke:#2f6b53,stroke-width:2px,color:#123321,font-weight:bold;
    classDef auto fill:#f6f8fa,stroke:#9aa7b4,color:#223140;
```

---

## 2. Detailed flow — Sarah's journey (6 scenes)

Legend: green = what Sarah sees · yellow = AI models · blue = data/metrics · gray italic = design rationale

```mermaid
flowchart TD
    subgraph S1["Scene 1 · The Still Anchor 🎯"]
        UI1["📱 'Tap the center of your dish to lock'"]:::ui
        S1a["Sarah taps center of chicken pile"] --> S1b["Capture raw pixel touchpoint"]
        S1b --> S1c["Normalize to fractional coords<br/>(X: 0.54, Y: 0.49)"]
        UI1 --> S1a
        S1c -.->|why| W1["Anchors the pipeline: ignore laptop,<br/>bottle, napkin — lock onto the food"]:::why
    end

    subgraph S2["Scene 2 · The 3-5s Arc 🌀"]
        UI2["📱 'Hold the button and scan slowly in an arc'"]:::ui
        S2a["Sarah records a 3-5s arc, 45° to top-down"] --> S2b["Capture 3-5s .mp4 clip"]
        S2b --> S2c["Multi-angle views create parallax"]
        UI2 --> S2a
        S2c -.->|why| W2["Structure-from-motion depth<br/>without LiDAR hardware"]:::why
    end

    subgraph S3["Scene 3 · The Edge Guard 🛡️"]
        UI3["📱 'Target Locked. Processing your dish...'"]:::ui
        S3a["Compress video to 720p"] --> S3b["Extract 15 evenly-spaced frames"]
        S3b --> S3c["Laplacian sharpness test per frame"]
        S3c --> S3d["Drop blurry frames, grab sharp neighbors"]
        S3d --> S3e["Bundle payload:<br/>video + (X,Y) + hint 'Chipotle chicken bowl'"]
        UI3 --> S3a
    end

    subgraph S4["Scene 4 · Triage and the Split ☁️"]
        UI4["📱 'Bowl Detected! Analyzing ingredient volume...'"]:::ui
        S4a["FastAPI unwraps payload on GPU cloud"] --> S4b["Orchestration Agent reads hint"]
        S4b --> S4split["Split into 3 parallel vision tracks"]
        S4b --> S4dec{"Text hint present?"}
        S4dec -->|"Yes: 'Chipotle'"| PRESET["Load preset container<br/>Diameter 20.3 cm"]:::data
        S4dec -->|"No"| YOLOREF["Scale from YOLOv11<br/>reference object (fork / pen)"]:::data
        UI4 --> S4a
    end

    subgraph VIS["Parallel Vision Tracks 🧠 (turnaround < 2s)"]
        direction LR
        SAM["SAM 2 · The Tracker<br/>tap coords lock the bowl,<br/>streaming memory tracks mask x15 frames"]:::model
        YOLO["YOLOv11 · The Scale Anchor<br/>find standard reference object"]:::model
        DEPTH["Depth Anything V2 · The Depth Map<br/>dense relative depth grid"]:::model
    end

    subgraph S5["Scene 5 · The Math of Volumetric Space 📐"]
        S5a["Overlay SAM 2 mask onto depth map"] --> S5b["Cut away desk and background"]
        S5b --> S5c["Establish metric multiplier<br/>1 pixel = 0.05 cm"]
        S5c --> S5d["Measure depth: bowl rim to chicken peak"]
        S5d --> S5e["Integrate thousands of pixel columns"]
        S5e --> S5f["Total food volume = 580 cm3 (mL)"]:::data
        S5f -.->|why| W5["True volume, no NeRF /<br/>Gaussian Splat 3D-mesh overkill"]:::why
    end

    subgraph S6["Scene 6 · The Payoff 🥣"]
        S6a["Multimodal LLM + hint reads crispest frame<br/>50% rice · 25% chicken · 15% beans · 10% guac"] --> S6b["Multiply 580 mL by ingredient ratios"]
        S6b --> S6c["Apply density DB: volume to grams"]
        S6c --> S6d["Pull macros from USDA database"]
        S6d --> UI6["📱 640 Calories Logged!<br/>45g Protein · 62g Carbs · 18g Fat"]:::ui
        UI6 -.->|why| W6["Hint solves invisible ingredients:<br/>hidden oils, seasoning, buried items"]:::why
    end

    S1c --> S2a
    S2c --> S3a
    S3e --> S4a
    S4split --> SAM & YOLO & DEPTH
    YOLO --> YOLOREF
    PRESET --> S5c
    YOLOREF --> S5c
    SAM --> S5a
    DEPTH --> S5a
    S5f --> S6a

    classDef ui fill:#dff0e8,stroke:#2f6b53,stroke-width:1.5px,color:#123321,font-weight:bold;
    classDef model fill:#fff3cd,stroke:#b8860b,color:#3a2f00;
    classDef data fill:#e6ecff,stroke:#3b5ba5,color:#12204a;
    classDef why fill:#f5f5f5,stroke:#c4c4c4,color:#555,font-style:italic;
```
