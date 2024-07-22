function makeApiRequest() {
    fetch('https://app.akto.io/api/resetAllCustomAuthTypes', {
        method: 'POST',
        headers: {
            'X-API-KEY': '6HSw1lpPAvO0HAIvcMC8eRORXOLaoS1JkTxWIQrb'
        }
    })
    .then(response => response.json())
    .then(data => {
        console.log('Success:', data);
    })
    .catch((error) => {
        console.error('Error:', error);
    });
}

// Make the API request every 2 minutes (120000 milliseconds)
setInterval(makeApiRequest, 120000);

// Optionally, make the first request immediately
makeApiRequest();
