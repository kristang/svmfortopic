#' @name svmfortopic
#' @title Package providing all data and programs used in the topic XXX by
#' Andreas Keller Leth Laursen
#' @docType package
#' @description Provides all data used in the project topic by Andreas Keller
#' Leth Laursen from public sources. Further all programs are included as well
#' as tables and graphs.
#' @details
#' \tabular{ll}{
#'   Type:    \tab Package     \cr
#'   Version: \tab 1.0         \cr
#'   Date:    \tab 2014-10-24  \cr
#'   License: \tab GPL         \cr
#'   }
#' @author Andreas Keller Leth Laursen
#' Maintainer Andreas Keller Leth Laursen <andreas.keller[at]gmail.com>
NULL

#' Function scraping various spotprices and volumes from the Epexspot website
#'
#' @param from_date A string with the start date of the desired series
#' @param to_date A string with the end date of the desired series
#' @param country A string with the desired country iso id. Takes the values DE, 
#' FR and CH. Default is DE.
#' @param market A string indicating market type. Takes the values Spot and
#' Intraday. Deafult is Spot.
#' @param contract A string indicating contract type for intraday. Take the
#' values H and Q. Default is H.
#' @param filter_missing A bolean, determining wether or not to replace missing
#' values.
#' @return a dataframe containing the dates, hours, spot and volumes
#' @export
scrape_epex <- function(from_date, to_date, country = "DE", market = "Spot",
                        contract = "H", filter_missing = TRUE)
{
  cat("Initialising scraping routine, getting dates ...\n")
  time_stamp <- Sys.time()
  
  if (market == "Spot") {
    date_scr <- seq(as.Date(from_date) -6, as.Date(to_date) -6, by = 1) %>%
      as.character
  } else if (market == "Intraday") {
    date_scr <- seq(as.Date(from_date), as.Date(to_date), by = 1) %>%
      as.character
  } else {
    stop("Market not recognised")
  }
  
  data_out <- list()
  for (ii in 1:length(date_scr)) {
    if (market == "Spot") {
      
      epex_sp <-
        html(paste0("http://www.epexspot.com/en/market-data/auction/auction-ta",
                    "ble/",
                    date_scr[ii],
                    "/",
                    country))
      
      data_scr <- epex_sp %>%
        html_nodes("#tab_de td:nth-child(9)") %>%
        html_text %>%
        gsub(",", "", .) %>% 
        as.numeric
      
      # Summarise to handle October daylights savings, i.e. two hour 3.
      data_out[[ii]] <- data.frame(
        date = date_scr[ii] %>% as.Date %>% add(6),
        hour = if (length(data_scr) > 48) c(1:3, 3:24) else 1:24,
        spot = data_scr[c(TRUE, FALSE)],
        volume = data_scr[c(FALSE, TRUE)],
        created = time_stamp) %>%
        group_by(date, hour) %>%
        summarise(spot = mean(spot, na.rm = TRUE),
                  volume = mean(volume, na.rm = TRUE)) %>%
        ungroup
      
      cat(paste0(as.character(as.Date(date_scr[ii]) + 6), " ...\n"))
      
    } else if (market == "Intraday") {
      
      epex_sp <-
        html(paste0("http://www.epexspot.com/en/market-data/intraday/intraday-",
                    "table/",
                    date_scr[ii],
                    "/",
                    country))
      
      data_scr <- epex_sp %>%
        html_nodes("td:nth-child(6)") %>%
        html_text %>%
        gsub(",", "", .) %>% 
        as.numeric %>%
        head(-1)
      
      if (contract == "H") {
        
        data_scr <- data_scr[seq(1, length(data_scr), 5)]
        
        # Summarise to handle October daylights savings, i.e. two hour 3.
        data_out[[ii]] <- data.frame(
          date = date_scr[ii] %>% as.Date,
          hour = if (length(data_scr) > 24) c(1:3, 3:24) else 1:24,
          vwap = data_scr,
          created = time_stamp) %>%
          group_by(date, hour) %>%
          summarise(vwap = mean(vwap, na.rm = TRUE)) %>%
          ungroup
        
        cat(paste0(date_scr[ii], " ...\n"))
        
      } else if (contract == "Q") {
        
        data_scr <- data_scr[-seq(1, length(data_scr), 5)]
        
        # Summarise to handle October daylights savings, i.e. two hour 3.
        data_out[[ii]] <- data.frame(
          date = date_scr[ii] %>% as.Date,
          quarter = if (length(data_scr) > 96) c(1:12, 9:12, 13:96) else 1:96,
          vwap = data_scr,
          created = time_stamp) %>%
          group_by(date, quarter) %>%
          summarise(vwap = mean(vwap, na.rm = TRUE)) %>%
          ungroup
        
        cat(paste0(date_scr[ii], " ...\n"))
        
      } else {
        stop("Contract not recognised")
      }
      
    } else {
      stop("Market not recognised\n")
    }
  }
  if (market == "Spot") {
    data_out <- data_out %>%
      rbind_all %>%
      transmute(date,
                hour,
                price = if (filter_missing == TRUE) na_filter(spot) else spot,
                volume = if (filter_missing == TRUE) na_filter(volume) else volume)
  } else if (market == "Intraday") {
    data_out <- data_out %>%
      rbind_all %>%
      transmute(date,
                hour,
                price = if (filter_missing == TRUE) na_filter(vwap) else vwap)
  } else {
    stop("Please specify correct market type.")
  }
  
  cat("Data downloaded, exiting function\n")
  return(data_out)
}

#' Function replacing missing values (NA) using linear interpolation between
#' closest finite observations. If starting points are missing, they are
#' replaced by the closets observation possible.
#'
#' @param input_data An atomic vector containing data to be fixed.
#' @return An atomic vector filtered for missing values.
na_filter <- function(input_data) {
  cat("Replacing missing values\n")
    
  .idx <- which(is.na(input_data))
  
  if (length(.idx) > 0) {
    for (ii in 1:length(.idx)) {
      for (jj in 1:(length(input_data) - .idx[ii])) {
        if (!is.na(input_data[.idx[ii] + jj]) == TRUE) {
          .bp <- jj
          break
        }
      }
      if (is.null(.idx[ii - 1]) == TRUE) {
        input_data[.idx[ii]] <- input_data[.idx[ii] + .bp]
      } else {
        input_data[.idx[ii]] <- input_data[.idx[ii] - 1] +
          (input_data[.idx[ii] + .bp] - input_data[.idx[ii] - 1]) / (.bp + 1)
        cat(paste0("Replaced ", ii, "\n"))
      }
    }
  }
  cat("... Done\n")
  return(input_data)
}

#' Function getting holiday dummies
#' @param from_date A string with the start date of the desired series
#' @param to_date A string with the end date of the desired series
#' @param country A string with the desired country iso id. Takes the values DE, 
#' FR and CH. Default is DE.
#' @return output_frame A dataframe containing date and seleced countries.
#' @export
#' 
get_holi_dum <- function(from_date, to_date, country = "de") {
  cat("Getting dummies")
  
  csv_file <- system.file("csv/holidays.csv", package = "svmfortopic")
  output_frame <- read.csv(csv_file, sep = ";", stringsAsFactors = FALSE) %>%
    select(date, one_of(country)) %>%
    filter(date >= from_date & date <= to_date) %>%
    mutate(date = as.Date(date)) %>%
    set_names(c("date", "is_holiday"))
  
  cat(" ... Done\n")
  return(output_frame)
}

#' Function calculating the exponentially weighted moving average of the input
#' time series.
#' 
#' @param input_vector An atomic vector containing a time series.
#' @param lambda A double, the lambda parameter for the ewma. Default value is
#' 0.975
#' @return An atomic vector with the transformed data.
#' @export
ewma <- function(input_vector, lambda = 0.975) {
  output_vector <- input_vector
  for (ii in 2:length(input_vector)) {
    output_vector[ii] <- (1 - lambda) * input_vector[ii] +
      lambda * output_vector[ii - 1]
  }
  return(output_vector)
}

#' Function for filtering seasonalities based on XXX
#' 
#' @param input_frame A data frame containing the times series data.
#' @return data_filt Same dataframe with deseasonalised price
#' @export
long_run_trend_season <- function(input_frame) {  
  data_frame <- input_frame %>%
    transmute(price = price - mean(price),
              trend = 1:n(),
              ewma = ewma(price))
  
  # Run linear and non-linear combinations to obtain starting values.
  data_frame_init <- data_frame %>%
    transmute(price,
              trend = sin(2 * pi * (trend / 365 + 1)),
              ewma = ewma(price))
  out_init <- lm(price ~ trend + ewma,
                 data = data_frame_init) %>%
    tidy %>%
    use_series(estimate)    

  out_init_1 <- nls(price ~ (out_init[2] * sin(2 * pi * (trend / 365 + beta_2)) +
                              out_init[1] + out_init[3] * ewma),
                    data = data_frame,
                    start = list(
                      beta_2 = 1),
                    trace = TRUE,
                    control = list(
                      maxiter = 5000)) %>%
    tidy %>%
    use_series(estimate)
  
  data_frame_init_1 <- data_frame %>%
    transmute(price,
              trend = sin(2 * pi * (trend / 365 + out_init_1[1])),
              ewma = ewma(price))
  out_init_2 <- lm(price ~ trend + ewma,
                   data = data_frame_init_1) %>%
    tidy %>%
    use_series(estimate)
  
  # Run model
  trend_seas_fit <- nls(price ~ (beta_1 * sin(2 * pi * (trend / 365 + beta_2)) +
                                  beta_3 + beta_4 * ewma),
                        data = data_frame,
                        start = list(
                          beta_1 = out_init_2[2],
                          beta_2 = out_init_1[1],
                          beta_3 = out_init_2[1],
                          beta_4 = out_init_2[3]),
                        trace = TRUE,
                        algorithm = "default", # GN. Same convergence for "port"
                        control = list(
                          maxiter = 100,
                          tol = 1e-06,
                          printEval = TRUE)) %>%
    tidy %>%
    use_series(estimate)
  
  data_frame_post_LTSC <- input_frame %>%
    transmute(date,
              trend = 1:n(),
              ewma = ewma(price),
              price = price - (trend_seas_fit[1] * 
                                 sin(2 * pi * (trend / 365 + trend_seas_fit[2])) -
                                 trend_seas_fit[3] + trend_seas_fit[4] * ewma),
              trend_seas = (trend_seas_fit[1] * 
                              sin(2 * pi * (trend / 365 + trend_seas_fit[2])) -
                              trend_seas_fit[3] + trend_seas_fit[4] * ewma)) %>%
    select(-trend, -ewma)
              
}

#' Function calculating short run season
#' @param input_frame A data frame with a trend and a price
#' @export
#' 
short_run_season <- function(input_frame) {
  data_frame <- input_frame %>%
    left_join(get_holi_dum(head(input_frame$date, 1),
                           tail(input_frame$date, 1)),
              by = "date") %>%
    transmute(price,
              is_holiday,
              week_day = date %>% as.Date %>% format("%a") %>% as.factor)
  
  data_frame <- cbind(data_frame,
                      data.frame(model.matrix(~ week_day - 1,
                                               data = data_frame))) %>%
    select(-week_day, -week_dayMon)
  
  short_seas_fit <- lm(price ~ .,
                       data = data_frame)
  
  data_filt <- data.frame(date = input_frame$date,
                          price = short_seas_fit$residuals)
  
  return(data_filt)
}

#' Outlier filter function
#' 
#' @param data_input A data frame containing a price to be outlier filtered.
#' @param std_filt Number of standard deviations to filter on.
#' @export
outlier_filt <- function(input_frame, std_filt = 5)
{
  cat("Filtering Outliers\n")
  cat(paste0("Outliers outside of ", std_filt, " being replaced by NA"))
  data_transform <- input_frame
  data_transform$price[which(data_transform$price >
                               std_filt * sd(data_transform$price) |
                               data_transform$price <
                               - std_filt * sd(data_transform$price))
                       ] <- NA
  cat(" ... Done")
  output_frame <- data_transform %>% 
    mutate(price = na_filter(price))
  
  cat(" ... Outliers filtered")
  return(output_frame)
}

#' Function performing all calculation and creating all tables for topic report
#' 
do_study <- function(spot_data) {
  
  # Filter spot data
  spot_data_filtered <- spot_data %>%
    deseason_price() %>%
    outlier_filt()
  
  # Stationarity test, augmented Dickey-Fuller
  DF <- vector()
  for (ii in 1:48) {
    DF[ii] <- tseries::adf.test(spot_data_filtered$price, k = ii) %>%
      use_series(p.value)
  }
  
  # ARCH test
  
  
  # Forecasting 24 hours in one model
  
  # Forecasting each of the 24 hours in 24 models model
  
  # Forecasting the base using the base of all days
  
  # Forecasting the base using 24 previous observations (multicollinearity)
}

#' Function doing base part of study
#' 
#' @export
spot_base_study <- function() {
  
  # Take the mean across each day to find the base spot price
  data_frame <- data_spot %>%
    group_by(date) %>%
    summarise(price = mean(price, na.rm = TRUE)) %>%
    ungroup
  
  # Draw line plot to get feel of data series
  draw_line_plot(data_frame,
                 input = "price",
                 xlabel = "Year",
                 ylabel = "Base spot price, EUR/MWh")
  
  # Get unfiltered descriptive statistics
  descriptives <- data_frame %>%
    summarise(max = max(price),
              min = min(price),
              median = median(price, na.rm = TRUE),
              mean = mean(price, na.rm = TRUE),
              sd = sd(price, na.rm = TRUE))
  
  demean_data_frame <- data_frame %>%
    transmute(date,
              price = price - mean(price, na.rm = TRUE))
  
  # Plot autocorrelation
  draw_acf(demean_data_frame, 96)
  # Plot parellogram
  draw_periodogram(demean_data_frame)
  
  # Clearly we see a seasonal pattern at lag 7 and at freqency 0.14 -> period
  # 1/0.14 = 7.14. As such, we deseasonalise.
  
  # We separate the deseason into two parts, a LR trendseasonal term and a SR
  # (weekly) seasonal term. Starting with LR
  de_lrts_data_frame <- long_run_trend_season(demean_data_frame)
  
  # Plot estimated trendseas:
  draw_line_plot(de_lrts_data_frame,
                 input = "trend_seas",
                 xlabel = "Year",
                 ylabel = "Long run seasonal trend")
  
  # Plot detrended series
  draw_line_plot(de_lrts_data_frame,
                 input = "price",
                 xlabel = "Year",
                 ylabel = "Long run seasonal trend")
  
  deseason_data_frame <- short_run_season(de_lrts_data_frame)
  
  # Plot estimated deseason:
  draw_line_plot(deseason_data_frame,
                 input = "price",
                 xlabel = "Year",
                 ylabel = "Deseasonalised data")
  # Plot autocorrelation
  draw_acf(deseason_data_frame, 96)
  # Plot parellogram
  draw_periodogram(deseason_data_frame)
  
  # Select best arima model
  auto.arima(deseason_data_frame$price, max.p = 14, max.q = 14, max.order = 14, trace = TRUE)
  out <- list()
  for (ii in 1:4) {
    for (jj in 1:4) {
      tmp <- arima(deseason_data_frame$price, order = c(ii, 0, jj))
      print(paste("p: ", ii, ", q: ", jj, ", aic: ", tmp$aic))
      out[(ii - 1) * 7 + jj] <- data.frame(p = ii, q = jj, aic = tmp$aic)
    }
  }
}