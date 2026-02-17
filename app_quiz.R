library(shiny)
library(httr)
library(jsonlite)
library(shinyjs)

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

img_dir_path <- find_dir("demo-images")
www_path <- find_dir("www")

if (is.null(img_dir_path) || is.null(www_path)) {
  stop("Required directories ('demo-images', 'www') not found. Check project structure.")
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

#### UI ####
ui <- navbarPage(
  title = "🔬 Phyto-Plankton Lab",
  theme = shinythemes::shinytheme("flatly"),
  header = tags$head(
    useShinyjs(),
    tags$style(HTML("
      body { background-image: url('assets/bg.jpg'); background-size: cover; background-attachment: fixed; }
      .navbar { margin-bottom: 0; }
      .well { background-color: rgba(255, 255, 255, 0.9); border: none; box-shadow: 0 4px 15px rgba(0,0,0,0.2); }
      .plankton-img { width: 100%; height: 200px; object-fit: contain; background: #fdfdfd; border-radius: 5px; border: 1px solid #ddd; }
      .train-card { margin-bottom: 20px; transition: transform 0.2s; }
      .train-card:hover { transform: scale(1.02); }
      .score-box { padding: 10px; border-radius: 8px; margin-top: 8px; border: 1px solid #ddd; background: white; text-align: left;}
      .match-hit { background-color: #dff0d8 !important; border-left: 5px solid #3c763d; }
      .match-near { background-color: #fcf8e3 !important; border-left: 5px solid #8a6d3b; }
      .match-miss { background-color: #f2dede !important; border-left: 5px solid #a94442; }
      .truth-label { font-weight: bold; background: #2c3e50; color: white; padding: 4px 8px; border-radius: 4px; margin-bottom: 8px; display: block; }
      #loading-modal {
        position: fixed; top: 0; left: 0; width: 100%; height: 100%;
        background: rgba(255, 255, 255, 0.9); z-index: 9999;
        display: flex; flex-direction: column; align-items: center; justify-content: center;
      }
      .timer-badge { font-size: 0.8em; color: #666; float: right; }
    "))
  ),
  
  # --- TRAIN TAB ---
  tabPanel("🎓 Train Mode",
           fluidRow(
             column(3,
                    wellPanel(
                      h4("Learning Filters"),
                      selectInput("train_filter", "Select Species to Study:", choices = c("All", classes_model)),
                      helpText("Study the visual characteristics of each species to improve your identification skills.")
                    )
             ),
             column(9,
                    uiOutput("train_gallery")
             )
           )
  ),
  
  # --- TEST TAB ---
  tabPanel("🧪 Test Mode",
           hidden(
             div(id = "loading-modal",
                 img(src = "assets/loading_gif.gif", width = "120px"),
                 h3("Neural Network analyzing specimens..."),
                 div(id = "progress-status", style="font-weight: bold; color: #2980b9;")
             )
           ),
           fluidRow(
             lapply(1:3, function(i) {
               column(4, align = "center",
                      wellPanel(
                        h4(paste("Specimen", LETTERS[i])),
                        uiOutput(paste0("img_container_", i)),
                        hr(),
                        selectInput(paste0("user_guess_", i), "Classification:", choices = c("Choose..."="", classes_model)),
                        uiOutput(paste0("results_", i))
                      )
               )
             })
           ),
           fluidRow(
             column(12, align = "center",
                    actionButton("validate", "Validate Selections", class = "btn-success btn-lg"),
                    actionButton("reset", "New Specimens", class = "btn-info btn-lg", style="margin-left:15px;"),
                    br(), uiOutput("timing_ui")
             )
           )
  )
)

#### SERVER ####
server <- function(input, output, session) {
  
  # --- REACTIVE DATA ---
  quiz_data <- reactiveValues(imgs = NULL, ai = NULL, total_time = NULL)
  all_data <- get_all_images()
  
  # --- TRAIN LOGIC ---
  output$train_gallery <- renderUI({
    filtered <- if(input$train_filter == "All") all_data else all_data[all_data$label == input$train_filter, ]
    
    # Create a grid of images
    tagList(
      fluidRow(
        lapply(seq_len(nrow(filtered)), function(i) {
          column(3, class = "train-card",
                 div(style="background: white; padding: 10px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1);",
                     img(src = paste0("plankton/", sub(".*demo-images/", "", filtered$path[i])), class = "plankton-img"),
                     div(style="margin-top: 5px; font-weight: bold; text-align: center; color: #34495e;", filtered$label[i])
                 )
          )
        })
      )
    )
  })
  
  # --- TEST LOGIC ---
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
        full_p <- quiz_data$imgs$path[i]
        rel_p <- sub(".*demo-images/", "", full_p)
        img(src = paste0("plankton/", rel_p), class = "plankton-img")
      })
    })
  })
  
  observeEvent(input$reset, {
    refresh_quiz()
    output$timing_ui <- renderUI({ NULL })
    for(i in 1:3) {
      updateSelectInput(session, paste0("user_guess_", i), selected = "")
      output[[paste0("results_", i)]] <- renderUI({ NULL })
    }
  })
  
  observeEvent(input$validate, {
    show("loading-modal")
    global_start <- Sys.time()
    
    withProgress(message = 'Analyzing...', value = 0, {
      temp_results <- list()
      for(i in 1:3) {
        html("progress-status", sprintf("Processing specimen %d of 3...", i))
        setProgress(i/3)
        temp_results[[i]] <- collectPostFun(quiz_data$imgs$path[i])
      }
      quiz_data$ai <- temp_results
    })
    
    quiz_data$total_time <- round(as.numeric(difftime(Sys.time(), global_start, units = "secs")), 2)
    
    lapply(1:3, function(i) {
      output[[paste0("results_", i)]] <- renderUI({
        truth <- quiz_data$imgs$label[i]
        user  <- input[[paste0("user_guess_", i)]]
        ai_res <- quiz_data$ai[[i]]
        ai_top <- ai_res$top_5_labels[1]
        
        user_color <- if(user == truth) "match-hit" else if(truth %in% ai_res$top_5_labels) "match-near" else "match-miss"
        ai_color   <- if(ai_top == truth) "match-hit" else if(truth %in% ai_res$top_5_labels) "match-near" else "match-miss"
        
        div(style="margin-top: 15px;",
            span(class = "truth-label", paste("Truth:", truth)),
            div(class = paste("score-box", user_color), strong("Human:"), if(user=="") "None" else user),
            div(class = paste("score-box", ai_color), strong("AI:"), ai_top, 
                span(class="timer-badge", paste0(ai_res$time_sec, "s")))
        )
      })
    })
    
    output$timing_ui <- renderUI({
      div(style="margin-top: 20px; color: white; background: rgba(0,0,0,0.7); padding: 10px; border-radius: 20px; display: inline-block;",
          paste("Total Batch Analysis Time:", quiz_data$total_time, "seconds"))
    })
    
    hide("loading-modal")
  })
}

shinyApp(ui, server)