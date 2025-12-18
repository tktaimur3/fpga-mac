- Need to add an ending state that makes sure that 12 byte gap with TXCTL happens between adjacent frames
- The above will probably fix the issue of not seeing frames back to back when sending back to back (axi_tx_ready will trigger first instead of going to poll every time)
- Lost frames in that weird link disconnect edge case due to ??? figure it out perhaps

- Need to upload this code to github or something
- Get remote desktop tool?
