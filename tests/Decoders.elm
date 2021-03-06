module Decoders exposing (suite)

import Dict
import Expect exposing (Expectation)
import Json.Decode
import Model
import Test exposing (..)
import TestData
import Time


suite : Test
suite =
    describe "JSON Decoders"
        [ test "Decoding succeeds" <|
            \_ -> Expect.ok decoded
        , test "Has trains" <|
            expectTrains (Dict.size >> Expect.greaterThan 1)
        , test "Trains' line ids" <|
            expectAllTrains "Line ids are single letter" <|
                \{ lineId } -> String.length lineId == 1
        , test "Trains' home and end stations are correct" <|
            expectAllTrains "Home is LPV, end is PSL" <|
                \{ homeStationDeparture, endStationArrival } ->
                    (homeStationDeparture.stationShortCode == "LPV")
                        && (endStationArrival.stationShortCode == "PSL")
        , test "Trains stop first at dep, then at dest" <|
            expectAllTrains "Scheduled times with home < end" <|
                \{ homeStationDeparture, endStationArrival } ->
                    Time.posixToMillis homeStationDeparture.scheduledTime
                        < Time.posixToMillis endStationArrival.scheduledTime
        , describe "Accuracy of data"
            [ case decoded of
                Err _ ->
                    test "Decoding has failed" (\_ -> Expect.fail "Yes")

                Ok trains ->
                    case Model.sortedTrainList trains of
                        trainU1 :: trainA1 :: trainE :: trainA2 :: trainU2 :: rest ->
                            Test.concat
                                [ test "Trains are the expected lines" <|
                                    \_ ->
                                        Expect.equalLists [ "U", "A", "E", "A", "U" ]
                                            (List.map .lineId [ trainU1, trainA1, trainE, trainA2, trainU2 ])
                                , test "First train (U) is moving" <|
                                    \_ -> Expect.true "is not moving" trainU1.runningCurrently
                                , test "First train (U) is late" <|
                                    \_ -> Expect.equal (Just 4) trainU1.homeStationDeparture.differenceInMinutes
                                , test "Second train (A) is not moving" <|
                                    \_ -> Expect.false "is moving" trainA1.runningCurrently
                                , test "Second train (A) is cancelled" <|
                                    \_ -> Expect.true "is not cancelled" trainA1.cancelled
                                , test "Third train (E) is not moving" <|
                                    \_ -> Expect.false "is moving" trainE.runningCurrently
                                , test "Third train (E) is late" <|
                                    \_ -> Expect.equal (Just 2) trainE.homeStationDeparture.differenceInMinutes
                                , test "Fifth train (U) is moving" <|
                                    \_ -> Expect.true "is not moving" trainU2.runningCurrently
                                , test "Fifth train (U) is on time" <|
                                    \_ -> Expect.equal (Just 0) trainU2.homeStationDeparture.differenceInMinutes
                                ]

                        _ ->
                            test "List doesn't have enough trains" (\_ -> Expect.fail "Yes")
            ]
        ]


expectAllTrains : String -> (Model.Train -> Bool) -> () -> Expectation
expectAllTrains expString trainFn =
    expectTrains
        (\trains ->
            trains
                |> Dict.values
                |> List.all trainFn
                |> Expect.true ("All trains: " ++ expString)
        )


expectTrains : (Model.Trains -> Expectation) -> () -> Expectation
expectTrains =
    expectResult decoded


expectResult : Result e a -> (a -> Expectation) -> () -> Expectation
expectResult result exp _ =
    case result of
        Err err ->
            Expect.fail "Not an Ok result"

        Ok value ->
            exp value


decoded : Result Json.Decode.Error Model.Trains
decoded =
    Json.Decode.decodeString (Model.trainsDecoder { from = "LPV", to = "PSL" }) TestData.json
