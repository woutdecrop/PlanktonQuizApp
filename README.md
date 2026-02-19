# Phyto-Plankton Lab 🔬

An interactive Shiny application for exploring and classifying plankton images. Users can train on species, test their identification skills, and compare human guesses with AI predictions.

![Phyto-Plankton Lab](www/bg.jpg)

## Features

### Train Mode
- Browse a gallery of plankton images.
- Filter images by species to focus on specific classes.
- Hover effects and interactive cards for a polished UI.
- Learn visual characteristics of each species to improve identification skills.

### Test Mode
- Classify three random specimens per session.
- Human input via dropdown menus.
- Real-time AI predictions from a remote model endpoint.
- Top-5 AI predictions with probabilities displayed.
- Color-coded feedback: green = correct, yellow = near correct, red = incorrect.
- Batch analysis time displayed for each session.
- Loading modal while AI predictions are processed.

## Installation

1. Clone the repository:
git clone https://github.com/<your-username>/plankton-lab.git
cd plankton-lab

2. Install required R packages:
install.packages(c("shiny", "shinyjs", "httr", "jsonlite", "shinythemes"))

3. Ensure required directories exist:
- `demo-images/` → contains subfolders for each plankton species with images.
- `www/` → contains static assets such as background images and loading GIFs.

## Usage

1. Launch the Shiny app:
library(shiny)
runApp("app.R")

2. Navigate between tabs:
- **Train Mode** → browse and learn plankton images.
- **Test Mode** → classify specimens, compare your guesses with AI predictions, and view feedback.

3. Use filters and dropdowns to customize your experience and focus on specific species.

## File Structure

Plankton-Lab/
- app.R                   → main Shiny script
- demo-images/            → plankton image library
  - species_name/         → images per species
- www/                    → static assets (backgrounds, loading GIFs)
- README.md               → this file

## AI Integration

- Predictions are fetched from a REST endpoint (`predict_url_remote`).
- Returns top-5 predicted species with probabilities.
- Results are displayed alongside human guesses for comparison.

## Customization

- Update `classes_model` to include new species.
- Replace background or GIF assets in `www/`.
- Adjust UI styling in the Shiny `tags$style` section of the script.

## License

MIT License

## Acknowledgments

- Built with [Shiny](https://shiny.rstudio.com/), [shinyjs](https://deanattali.com/shinyjs/), [httr](https://cran.r-project.org/package=httr), and [jsonlite](https://cran.r-project.org/package=jsonlite).
- Designed to provide an interactive learning and testing experience for plankton classification.
