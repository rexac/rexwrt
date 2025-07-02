 'require rpc';
 
var callOnlineUsers = rpc.declare({
        object: 'luci',
        method: 'getOnlineUsers'
});
