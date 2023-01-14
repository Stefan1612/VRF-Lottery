import { ethers } from "ethers";
import { Typography, Box, Button } from "@mui/material";
const Home = (props) => {
  let unix_timestamp = props.startTime;
  // Create a new JavaScript Date object based on the timestamp
  // multiplied by 1000 so that the argument is in milliseconds, not seconds.
  var date = new Date(unix_timestamp * 1000);
  // Hours part from the timestamp
  var hours = date.getHours();
  // Minutes part from the timestamp
  var minutes = "0" + date.getMinutes();
  // Seconds part from the timestamp
  var seconds = "0" + date.getSeconds();

  var day = date.getDate();
  var month = date.getMonth() + 1;
  var year = date.getFullYear();

  // Will display time in 10:30:23 format
  var formattedTime =
    hours +
    ":" +
    minutes.substr(-2) +
    ":" +
    seconds.substr(-2) +
    "," +
    day +
    "," +
    month +
    "," +
    year;
  return (
    <Box id="HomeId">
      {/* <img id="image" src="https://c.pxhere.com/photos/c3/a0/casino_roulette_table_the_dealer_game_fun_addiction_pleasure-993952.jpg!d"></img> */}

      <Box>
        <Box paddingTop={10}>
          <Typography variant="h1" component="h3">
            {/* {props.isLotteryRunning} */}
            {props.currentState}
          </Typography>

          <Typography variant={"p"} component={"span"}>
            Last Lottery started at: {formattedTime}
          </Typography>
          <Typography>
            Minimun amount of time the Lottery is going to run:{" "}
            <Typography
              variant={"h3"}
              component={"h3"}
              sx={{ color: "#00e676" }}
            >
              {props.time} seconds
            </Typography>
          </Typography>
        </Box>

        <Box
          textAlign={"center"}
          marginTop={"10vh"}
          sx={{
            backgroundColor: "#424242",
            marginX: "17vw",
            borderRadius: "15px",
            padding: "calc(0.7vw + 0.7vh)",
          }}
        >
          <Box>
            <Typography component="h3" variant="h3">
              Current Price Pool in Ether:
            </Typography>
            <Typography
              component="span"
              variant="span"
              style={{ fontSize: "550%" }}
            >
              {props.currentPool} {ethers.constants.EtherSymbol}
            </Typography>
          </Box>
          <Box>
            <Typography variant={"H3"} component={"span"}>
              Entry cost: {props.price} ether
            </Typography>

            <br />
            <Typography component={"span"} variant={"p"}>
              <Button
                onClick={props.enterPoolContract}
                variant={"contained"}
                id="entryButton"
              >
                Buy Lottery Ticket
              </Button>
            </Typography>
          </Box>
        </Box>

        <Box
          marginTop={"5vh"}
          sx={{
            backgroundColor: "#424242",
            padding: "calc(0.7vw + 0.7vh)",
            borderRadius: "15px",
          }}
        >
          <Typography component={"h3"} variant={"h3"}>
            {props.winner === "0x0000000000000000000000000000000000000000"
              ? "The winner will be announced here"
              : "Congratulations " + props.winner + " you've won the price"}
            !
          </Typography>
        </Box>

        <Box>
          <Typography marginTop={"3vh"} component="p" variant="p">
            Current Participants: <Box>{props.playerArray}</Box>
          </Typography>
        </Box>
      </Box>
    </Box>
  );
};

export default Home;
