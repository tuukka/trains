module View exposing (Msg(..), view)

import Browser exposing (Document, UrlRequest)
import DateFormat
import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Http
import Icons
import Model exposing (..)
import RemoteData exposing (RemoteData(..), WebData)
import Stations
import Time exposing (Posix)
import Url exposing (Url)
import Url.Parser


type Msg
    = UpdateTime Posix
    | TimeZoneResponse Time.Zone
    | TrainsResponse (WebData Trains)
    | StationsResponse (WebData Stations)
    | UrlChange Url
    | LinkClicked UrlRequest


rem : Float -> Float
rem x =
    x * 16


ts : Int -> Float
ts scale =
    1.33 ^ toFloat scale * 16


tsPx : Int -> String
tsPx scale =
    String.fromFloat (ts scale) ++ "px"


whenJust : Maybe a -> (a -> Html msg) -> Html msg
whenJust value toHtml =
    case value of
        Just a ->
            toHtml a

        Nothing ->
            text ""


timelinessColor difference =
    if abs difference <= 1 then
        "var(--color-onTime)"

    else if abs difference <= 5 then
        "var(--color-slightlyOffSchedule)"

    else
        "var(--color-offSchedule)"


view : Model -> Document msg
view model =
    case model.route of
        SelectDepRoute ->
            selectDepPage model

        SelectDestRoute dep ->
            selectDestPage model dep

        ScheduleRoute from to ->
            schedulePage model ( from, to )


container : List (Html msg) -> List (Html msg)
container elements =
    [ div [ class "container" ] elements ]


selectDepPage : Model -> Document msg
selectDepPage model =
    { title = "Schedules! Helsinki region commuter trains"
    , body =
        container
            [ header [] [ h1 [] [ text "Select departure" ] ]
            , ul [ class "stations" ] <|
                List.map
                    (\( abbr, name ) ->
                        li [] [ a [ href ("#/" ++ abbr) ] [ text name ] ]
                    )
                    Stations.all
            ]
    }


selectDestPage : Model -> String -> Document msg
selectDestPage model dep =
    let
        url dest =
            "#/" ++ dep ++ "/" ++ dest

        linkText dest =
            Stations.findName dep
                |> Maybe.map (\name -> name ++ "–" ++ dest)
                |> Maybe.withDefault dest
    in
    { title = "Select destination – Schedules!"
    , body =
        container
            [ header [] [ h1 [] [ text "Select departure" ] ]
            , ul [ class "stations" ] <|
                List.map
                    (\( abbr, name ) ->
                        li [] [ a [ href (url abbr) ] [ text (linkText name) ] ]
                    )
                    (Stations.matching dep)
            ]
    }


schedulePage : Model -> ( String, String ) -> Document msg
schedulePage model ( from, to ) =
    let
        heading =
            stationName model.stations from ++ "—" ++ stationName model.stations to
    in
    { title = heading ++ " – Schedules!"
    , body =
        container
            [ case model.trains of
                Success trains ->
                    trainsView model ( from, to ) heading trains

                Failure err ->
                    div
                        []
                        [ header [] [ text "Oh noes, an error!" ]
                        , case err of
                            Http.NetworkError ->
                                text "It's the network."

                            Http.Timeout ->
                                text "Helloooo? (There was no response.)"

                            Http.BadUrl _ ->
                                text "It's not you, it's me. I have the server address wrong."

                            Http.BadStatus _ ->
                                text "Whoops, looks like the server didn't like the request."

                            Http.BadPayload _ _ ->
                                text "Ouch, the server responded with strange contents."
                        ]

                Loading ->
                    header [] [ text "Loading" ]

                _ ->
                    text ""
            ]
    }


trainsView : Model -> ( String, String ) -> String -> Trains -> Html msg
trainsView model ( from, to ) heading trains =
    let
        rightDirection =
            trains
                |> Model.sortedTrainList
    in
    div [ class "trains" ] <|
        [ header []
            [ a
                [ class "back-link", href "#/" ]
                [ text "‹" ]
            , h1 [] [ text heading ]
            , a
                [ class "swap-link", href ("#/" ++ to ++ "/" ++ from) ]
                [ Icons.swap ]
            ]
        ]
            ++ List.map (trainRow model ( from, to )) rightDirection


trainRow :
    { a | zone : Time.Zone, stations : Stations, currentTime : Posix }
    -> ( String, String )
    -> Train
    -> Html msg
trainRow { zone, stations, currentTime } ( from, to ) train =
    let
        currentStation =
            train.timetableRows
                |> List.filter (.actualTime >> (/=) Nothing)
                |> List.reverse
                |> List.head

        ( homeStationArrival, homeStationDeparture ) =
            train.timetableRows
                |> List.filter (.stationShortCode >> (==) from)
                |> (\homeStationRows ->
                        ( homeStationRows |> List.filter (.rowType >> (==) Arrival) |> List.head
                        , homeStationRows |> List.filter (.rowType >> (==) Departure) |> List.head
                        )
                   )

        homeStationArrivingIn =
            homeStationArrival
                |> Maybe.map .liveEstimateTime
                |> Maybe.withDefault (Maybe.map .scheduledTime homeStationArrival)
                |> Maybe.map
                    (\date ->
                        (Time.posixToMillis date - Time.posixToMillis currentTime)
                            |> prettyMinutes
                    )

        homeStationLiveEstimate =
            homeStationDeparture
                |> Maybe.map .liveEstimateTime
                |> Maybe.andThen identity

        endStation =
            train.timetableRows
                |> List.filter
                    (\row -> row.rowType == Arrival && row.stationShortCode == to)
                |> List.head

        statusInfo station =
            whenJust station.differenceInMinutes (statusInfoBadge station)

        statusInfoBadge station n =
            let
                name =
                    stationName stations station.stationShortCode
            in
            div
                [ class "train-status-badge"
                , style "background-color" (timelinessColor n)
                ]
                [ text (formatDifference (station.differenceInMinutes |> Maybe.withDefault 0) name) ]
    in
    div [ class "train" ]
        [ div [ class "train-content" ]
            [ div [ classList [ ( "train-name", True ), ( "is-running", train.runningCurrently ) ] ]
                [ text train.lineId ]
            , div [ class "train-stations" ]
                [ whenJust homeStationDeparture (stationRow zone stations)
                , div [ class "train-stations-separator" ] [ text "︙" ]
                , whenJust endStation (stationRow zone stations)
                ]
            , div [ class "train-status" ] <|
                case ( homeStationArrivingIn, currentStation ) of
                    ( Just time, Just station ) ->
                        [ div [ class "train-status-arriving" ]
                            [ text "Arrives in" ]
                        , div [ class "train-status-time" ]
                            [ text time ]
                        ]

                    _ ->
                        []
            ]
        , currentStation
            |> Maybe.map statusInfo
            |> Maybe.withDefault (text "")
        ]


stationRow : Time.Zone -> Stations -> TimetableRow -> Html msg
stationRow zone stations station =
    let
        name =
            stationName stations station.stationShortCode
    in
    div
        [ class "train-stations-row" ]
        [ case ( station.liveEstimateTime, station.differenceInMinutes ) of
            ( Just estimate, Just n ) ->
                div
                    [ class "train-stations-estimate" ]
                    [ div [ style "color" (timelinessColor n) ]
                        [ text <| prettyTime zone estimate ]
                    , if n /= 0 then
                        div [ class "train-stations-scheduled-inaccurate" ]
                            [ text <| prettyTime zone station.scheduledTime ]

                      else
                        text ""
                    ]

            _ ->
                div [ class "train-stations-estimate" ]
                    [ text <| prettyTime zone station.scheduledTime ]
        , div [] [ text name ]
        ]


stationName : Stations -> String -> String
stationName stations shortCode =
    stations
        |> Dict.get shortCode
        |> Maybe.withDefault shortCode


formatDifference : Int -> String -> String
formatDifference n name =
    let
        suffix =
            " in " ++ name
    in
    if abs n <= 1 then
        "On time" ++ suffix

    else if n < 0 then
        (String.fromInt (abs n) ++ " min early") ++ suffix

    else
        (String.fromInt n ++ " min late") ++ suffix


prettyMinutes : Int -> String
prettyMinutes timeDiff =
    DateFormat.format
        [ DateFormat.minuteNumber
        , DateFormat.text ":"
        , DateFormat.secondFixed
        ]
        Time.utc
        (Time.millisToPosix timeDiff)


prettyTime : Time.Zone -> Posix -> String
prettyTime =
    DateFormat.format
        [ DateFormat.hourMilitaryNumber
        , DateFormat.text "."
        , DateFormat.minuteFixed
        ]
