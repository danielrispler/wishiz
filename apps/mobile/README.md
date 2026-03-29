# Wishiz — Digital Concierge & Wishlist Manager

**Wishiz** is a premium, editorial-style wishlist manager designed to treat user desires not as a database, but as a personal gallery. This Flutter application is built following the ["The Curated Pulse"](https://stitch.goog/wishiz) design system, emphasizing breathable white space, tonal layering, and sophisticated typography.

## ✨ Core Design Principles: "The Curated Pulse"

- **The Editorial Voice**: Using **Manrope** for headlines to provide an authoritative, premium feel.
- **The Functional Voice**: Using **Inter** for descriptions and metadata to ensure high legibility.
- **No-Line Rule**: We avoid standard 1px borders. Hierarchy is defined strictly through background shifts and tonal layering (using the `surface` to `surface-container` scale).
- **Glassmorphism**: Signature floating navigation and hero moments utilize backdrop blurs (20px) and subtle gradients.
- **Ambient Depth**: Traditional heavy shadows are replaced by ambient, diffused lighting effects.

## 🏗️ Architecture

The app uses a **Feature-Based Architecture**:

```
lib/
  core/           # Design system (theme, colors, constants)
  features/       # Business modules
    home/         # Main Dashboard & Creation logic
      presentation/
        screens/
        widgets/
```

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (>= 3.0.0)
- Dart SDK (>= 3.0.0)

### Installation & Run

1. **Initialize Project Assets** (if not already done):
   ```bash
   flutter create .
   ```

2. **Fetch Dependencies**:
   ```bash
   flutter pub get
   ```

3. **Check Quality**:
   ```bash
   flutter analyze
   ```

4. **Run Application**:
   ```bash
   # For Chrome/Web
   flutter run -d chrome

   # For Mobile (ensure emulator/device is connected)
   flutter run
   ```

## 🎨 Design System Details

- **Base Surface**: `#FAF4FF` (Lavender-Smoke)
- **Primary Gradient**: `#4647D3` to `#9396FF`
- **Text Primary**: `#302950` (Purple-tinted Depth)
- **Card Corners**: `xl` (24px)