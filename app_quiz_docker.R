library(shiny)
library(httr)
library(jsonlite)
library(shinyjs)
library(shinythemes)

# ============================================================
# CONFIG
# ============================================================

predict_url_remote <- "http://127.0.0.1:5000/v2/models/planktonclas/predict/?ckpt_name=final_model.h5"
# ============================================================
# DOCKER MANAGEMENT
# ============================================================
# ============================================================
# ROBUST DOCKER MANAGEMENT (FIXED)
# ============================================================

docker_container_name <- "phyto_classifier_container"
docker_image <- "ai4oshub/phyto-plankton-classification:dev-cpu"
health_url <- "http://127.0.0.1:5000/api"

check_api_available <- function() {
  tryCatch({
    res <- httr::GET(health_url, timeout(3))
    httr::status_code(res) == 200
  }, error = function(e) FALSE)
}
container_exists <- function() {
  res <- system(
    sprintf("docker ps -a --filter name=%s --format '{{.Names}}'",
            docker_container_name),
    intern = TRUE
  )
  docker_container_name %in% res
}

container_running <- function() {
  res <- system(
    sprintf("docker ps --filter name=%s --format '{{.Names}}'",
            docker_container_name),
    intern = TRUE
  )
  docker_container_name %in% res
}
start_container <- function() {
  
  cat("🔍 Checking Docker container...\n")
  
  # Inspect container status
  inspect_cmd <- sprintf(
    "docker inspect -f \"{{.State.Status}}\" %s",
    docker_container_name
  )
  
  status <- tryCatch(
    suppressWarnings(system(inspect_cmd, intern = TRUE)),
    error = function(e) character(0)
  )
  
  # If inspect fails, container does not exist
  if (length(status) == 0) {
    
    cat("📦 Creating new Docker container...\n")
    
    system(sprintf(
      "docker run -d -p 5000:5000 --name %s %s",
      docker_container_name,
      docker_image
    ))
    
    return(invisible())
    
  }
  
  status <- status[1]  # take first line only
  
  if (status == "running") {
    
    cat("✅ Container already running.\n")
    
  } else if (status == "exited") {
    
    cat("▶ Restarting existing container...\n")
    system(sprintf("docker start %s", docker_container_name))
    
  } else {
    
    cat("⚠ Container in state:", status, "\n")
  }
}

wait_for_api <- function(timeout_sec = 120) {
  
  cat("⏳ Waiting for API to become ready (can take ~1 min first time)...\n")
  
  start_time <- Sys.time()
  
  repeat {
    
    if (check_api_available()) {
      cat("✅ API is ready.\n")
      return(TRUE)
    }
    
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    
    if (elapsed > timeout_sec) {
      return(FALSE)
    }
    
    Sys.sleep(3)
  }
}

# ============================================================
# TEST PREDICTION
# ============================================================

test_prediction <- function(test_image_path) {
  cat("🧪 Testing prediction...\n")
  
  tryCatch({
    res <- POST(
      url = predict_url_remote,
      body = list(image = upload_file(test_image_path)),
      encode = "multipart"
    )
    
    json <- fromJSON(content(res, as = "text", encoding = "UTF-8"))
    
    if (!is.null(json$predictions$pred_lab)) {
      cat("✅ Prediction test successful.\n")
      return(TRUE)
    }
    
    FALSE
    
  }, error = function(e) FALSE)
}

# ============================================================
# PATH SETUP
# ============================================================

find_dir <- function(target) {
  if (dir.exists(target)) return(normalizePath(target))
  parent1 <- file.path("..", target)
  if (dir.exists(parent1)) return(normalizePath(parent1))
  parent2 <- file.path("..", "..", target)
  if (dir.exists(parent2)) return(normalizePath(parent2))
  return(NULL)
}

img_dir_path <- find_dir("images")
www_path <- find_dir("www")

if (is.null(img_dir_path) || is.null(www_path)) {
  stop("Required directories ('images', 'www') not found.")
}

addResourcePath("assets", www_path)
addResourcePath("plankton", img_dir_path)

classes_model <- list.dirs(img_dir_path,
                           full.names = FALSE,
                           recursive = FALSE)

# ============================================================
# 🚀 STARTUP VALIDATION
# ============================================================
cat("============================================\n")
cat("🚀 Initializing Phyto-Plankton Classifier\n")
cat("============================================\n")

start_container()

if (!wait_for_api()) {
  stop("❌ API failed to start within timeout.\nCheck: docker logs phyto_classifier_container")
}

if (!check_api_available()) {
  start_container()
  if (!wait_for_api()) {
    stop("❌ API failed to start within timeout.")
  }
}

# Test using first available image
test_image <- list.files(img_dir_path,
                         pattern="\\.(jpg|png|jpeg)$",
                         recursive=TRUE,
                         full.names=TRUE)[1]

if (is.na(test_image) || !file.exists(test_image)) {
  stop("❌ No test image found.")
}

if (!test_prediction(test_image)) {
  stop("❌ Prediction test failed. Classifier not functioning.")
}

cat("🎉 System ready. Launching Shiny app...\n\n")


# --- ROBUST PATH DETECTION ---
base_dir <- getwd()
find_dir <- function(target) {
  if (dir.exists(target)) return(normalizePath(target))
  parent1 <- file.path("..", target)
  if (dir.exists(parent1)) return(normalizePath(parent1))
  parent2 <- file.path("..", "..", target)
  if (dir.exists(parent2)) return(normalizePath(parent2))
  return(NULL)
}

img_dir_path <- find_dir("images")
www_path <- find_dir("www")

if (is.null(img_dir_path) || is.null(www_path)) {
  stop("Required directories ('images', 'www') not found. Check project structure.")
}


addResourcePath("assets", www_path)
addResourcePath("plankton", img_dir_path)

#### DYNAMIC CLASSES ####
classes_model <- list.dirs(img_dir_path, full.names = FALSE, recursive = FALSE)
predict_url_remote <- "http://127.0.0.1:5000/v2/models/planktonclas/predict/?ckpt_name=final_model.h5"

# --- HELPER FUNCTIONS ---
get_all_images <- function() {
  df_list <- lapply(classes_model, function(cl) {
    path <- file.path(img_dir_path, cl)
    files <- list.files(path, pattern = "\\.(jpg|png|jpeg)$", full.names = TRUE)
    if(length(files) > 0) {
      data.frame(path = gsub("\\\\", "/", files), label = cl, stringsAsFactors = FALSE)
    }
  })
  do.call(rbind, df_list)
}

sample_images <- function() {
  all_imgs <- get_all_images()
  # Sample 3 random images across different classes
  all_imgs[sample(nrow(all_imgs), 3), ]
}

collectPostFun <- function(img.path) {
  out <- list(error = TRUE, top_5_labels = c("Connection Error"), top_5_probs = c(0), time_sec = 0)
  t_start <- Sys.time()
  try({
    res <- POST(url = predict_url_remote, body = list(image = upload_file(img.path)), encode = "multipart")
    json <- fromJSON(content(res, as = "text", encoding = "UTF-8"))
    out$top_5_labels <- json$predictions$pred_lab[[1]]
    out$top_5_probs <- json$predictions$pred_prob[[1]]
    out$error <- FALSE
  }, silent = TRUE)
  out$time_sec <- round(as.numeric(difftime(Sys.time(), t_start, units = "secs")), 2)
  return(out)
}

# ============================================================
# UI
# ============================================================

ui <- navbarPage(
  title = "🔬 Phyto-Plankton Lab",
  theme = shinytheme("flatly"),
  header = tags$head(useShinyjs()),
  
  tabPanel("🎓 Train Mode",
           fluidRow(
             column(3,
                    wellPanel(
                      h4("Learning Filters"),
                      selectInput("train_filter",
                                  "Select Species to Study:",
                                  choices = c("All", classes_model))
                    )
             ),
             column(9, uiOutput("train_gallery"))
           )
  ),
  
  tabPanel("🧪 Test Mode",
           fluidRow(
             lapply(1:3, function(i) {
               column(4, align = "center",
                      wellPanel(
                        h4(paste("Specimen", LETTERS[i])),
                        uiOutput(paste0("img_container_", i)),
                        hr(),
                        selectInput(paste0("user_guess_", i),
                                    "Classification:",
                                    choices = c("Choose..."="", classes_model)),
                        uiOutput(paste0("results_", i))
                      )
               )
             })
           ),
           fluidRow(
             column(12, align = "center",
                    actionButton("validate", "Validate Selections",
                                 class = "btn-success btn-lg"),
                    actionButton("reset", "New Specimens",
                                 class = "btn-info btn-lg",
                                 style="margin-left:15px;"),
                    br(),
                    uiOutput("timing_ui")
             )
           )
  )
)

# ============================================================
# SERVER
# ============================================================

server <- function(input, output, session) {
  
  quiz_data <- reactiveValues(imgs = NULL, ai = NULL, total_time = NULL)
  all_data <- get_all_images()
  
  # TRAIN
  output$train_gallery <- renderUI({
    filtered <- if(input$train_filter == "All")
      all_data
    else
      all_data[all_data$label == input$train_filter, ]
    
    fluidRow(
      lapply(seq_len(nrow(filtered)), function(i) {
        column(3,
               img(src = paste0("plankton/",
                                sub(".*images/", "", filtered$path[i])),
                   style="width:100%; height:200px; object-fit:contain;"),
               div(style="text-align:center; font-weight:bold;",
                   filtered$label[i])
        )
      })
    )
  })
  
  # QUIZ
  refresh_quiz <- function() {
    quiz_data$imgs <- sample_images()
    quiz_data$ai <- list()
    quiz_data$total_time <- NULL
  }
  
  refresh_quiz()
  
  observe({
    req(quiz_data$imgs)
    lapply(1:3, function(i) {
      output[[paste0("img_container_", i)]] <- renderUI({
        img(src = paste0("plankton/",
                         sub(".*images/", "", quiz_data$imgs$path[i])),
            style="width:100%; height:200px; object-fit:contain;")
      })
    })
  })
  
  observeEvent(input$reset, {
    refresh_quiz()
    output$timing_ui <- renderUI({ NULL })
    lapply(1:3, function(i) {
      updateSelectInput(session,
                        paste0("user_guess_", i),
                        selected = "")
      output[[paste0("results_", i)]] <- renderUI({ NULL })
    })
  })
  
  observeEvent(input$validate, {
    
    if (!check_api_available()) {
      showNotification(
        "⚠ Classifier container not running. Attempting to start Docker...",
        type = "warning",
        duration = 5
      )
    }
    
    global_start <- Sys.time()
    
    temp_results <- lapply(1:3, function(i) {
      collectPostFun(quiz_data$imgs$path[i])
    })
    
    quiz_data$ai <- temp_results
    quiz_data$total_time <- round(
      as.numeric(difftime(Sys.time(), global_start, units = "secs")), 2)
    
    lapply(1:3, function(i) {
      output[[paste0("results_", i)]] <- renderUI({
        truth <- quiz_data$imgs$label[i]
        user  <- input[[paste0("user_guess_", i)]]
        ai_top <- quiz_data$ai[[i]]$top_5_labels[1]
        
        div(
          strong("Truth:"), truth, br(),
          strong("Human:"), if(user=="") "None" else user, br(),
          strong("AI:"), ai_top
        )
      })
    })
    
    output$timing_ui <- renderUI({
      div(paste("Total Batch Analysis Time:",
                quiz_data$total_time, "seconds"))
    })
  })
}

shinyApp(ui, server)