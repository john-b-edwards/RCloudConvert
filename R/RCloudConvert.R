#' @title convert_file
#'
#' @details converts a specified file -- either on a local machine, uploaded to
#' an s3 bucket, or in an FTP server -- using CloudConvert's V2 API. This is a
#' fork of the original RCloudConvert package, maintained by John Edwards.
#'
#' @param api_key CloudConvert V2 API key.
#' @param input_format The format of the input file.
#' @param output_format The format the file should be converted to.
#' @param input Set the method of uploading the input file. Possible
#' @param file Input file destination (including the name of file with
#' extension).
#' @param dest_file Name where the downloaded file is saved (including the name
#' of file with extension).
#' @param input_s3_accesskeyid The Amazon S3 accessKeyId (Required when input is
#' s3).
#' @param input_s3_secretaccesskey The Amazon S3 secretAccessKey (Required when
#' input is s3).
#' @param input_s3_bucket The Amazon S3 bucket where to download the input file
#' or upload the output file (Required when input is s3).
#' @param input_ftp_host The FTP server host (Required when input is ftp).
#' @param input_ftp_port The port the FTP server is bind to (Required when input
#' is ftp).
#' @param input_ftp_user FTP username (Required when input is ftp).
#' @param input_ftp_password FTP password (Required when input is ftp).
#' @export
#' @examples
#' \dontrun{
#' convert_file(api_key=api_key,
#'              input_format = "jpg",
#'              output_format = "pdf",
#'              input="upload",
#'              file="input file location",
#'              dest_file = "destination file location")
#' }

convert_file = function (api_key,
                         input_format,
                         output_format,
                         input,
                         file,
                         dest_file,
                         input_s3_accesskeyid = NA_character_,
                         input_s3_secretaccesskey = NA_character_,
                         input_s3_bucket = NA_character_,
                         input_s3_region = NA_character_,
                         input_ftp_host = NA_character_,
                         input_ftp_port = NA_character_,
                         input_ftp_user = NA_character_,
                         input_ftp_password = NA_character_)
{
  #' parse initial input options
  #' previous function only supported these options, though there are a few we
  #' can support later down the line
  if (toupper(input) %in% c("DOWNLOAD", "URL")) {
    import = list(operation = "import/url", file = file)
  }
  else if (toupper(input) %in% c("UPLOAD")) {
    import = list(operation = "import/upload")
  }
  else if (toupper(input) %in% c("S3")) {
    import = list(
      operation = "import/s3",
      access_key_id = input_s3_accesskeyid,
      secret_access_key = input_s3_secretaccesskey,
      bucket = input_s3_bucket,
      region = input_s3_region,
      filename = file
    )
  }
  else if (toupper(input) %in% c("FTP")) {
    import = list(
      operation = "import/sftp",
      host = input_ftp_host,
      username = input_ftp_user,
      file = file
    )
  }
  else {
    cli::cli_abort("Please ensure `input` is one of \"URL\", \"Upload\", \"s3\", or \"FTP\".")
  }
  # parse optional arguments
  if (toupper(input) %in% c("FTP") & !is.na(input_ftp_port)) {
    import[[length(import) + 1]] <- input_ftp_port
    names(import)[[length(import)]] <- "port"
  }
  if (toupper(input) %in% c("FTP") & !is.na(input_ftp_port)) {
    import[[length(import) + 1]] <- input_ftp_password
    names(import)[[length(import)]] <- "password"
  }
  # create job
  r <-
    httr::POST(
      "https://api.cloudconvert.com/v2/jobs",
      httr::add_headers(
        Authorization = glue::glue("Bearer {api_key}"),
        `content-type` = "application/json"
      ),
      body = list(tasks = list(
        import = import,
        convert = list(
          operation = "convert",
          input = "import",
          input_format = tolower(input_format),
          output_format = tolower(output_format)
        ),
        export = list(operation = "export/url", input = "convert")
      )),
      encode = "json"
    )
  # grab and store job id so we can access it again later
  job_id <- httr::content(r)$data$id
  # if uploading, upload file
  if (toupper(input) %in% c("UPLOAD")) {
    upload_task_id <- httr::content(r)$data$tasks[[1]]$id
    # grab the upload task id
    r <-
      httr::GET(
        glue::glue(
          "https://api.cloudconvert.com/v2/tasks/{upload_task_id}"
        ),
        httr::add_headers(Authorization = glue::glue("Bearer {api_key}"))
      )
    # grab the upload form
    form <- httr::content(r)$data$result$form
    port_url <- form$url
    params <- form$parameters
    # add the file to the upload form
    params[[length(params) + 1]] <- httr::upload_file(file)
    names(params)[[length(params)]] <- "file"
    
    # Remove the Authorization header for the POST request to S3
    r <- httr::POST(port_url, body = params)
    
    if (r$status_code != 201) {
      stop(
        "Problem uploading file to CloudConvert's storage: HTTP Status ",
        r$status_code,
        ". Response: ",
        httr::content(r, "text"),
        call. = FALSE
      )
    }
    
  }
  # fetch the job with the /wait endpoint, will wait until the job is done before processing
  r <-
    httr::GET(
      glue::glue("https://api.cloudconvert.com/v2/jobs/{job_id}/wait"),
      httr::add_headers(Authorization = glue::glue("Bearer {api_key}"))
    )
  # grab file url on cloudconvert
  file_url <- httr::content(r)$data$tasks[[1]]$result$files[[1]]$url
  # download file
  download.file(url = file_url,
                destfile = dest_file,
                mode = "wb")
}
