#!/usr/bin/env dub
/+ dub.sdl:
dependency "vibe-d" version="~>0.9.4"
versions "VibeHighEventPriority"
+/
module ipfs;

import vibe.vibe;
import vibe.internal.interfaceproxy : asInterface;

import std.algorithm;
import std.array;
import core.sync.mutex;

static immutable GATEWAY_LIST = [
    "https://ipfs.io",
    "https://dweb.link",
    "https://gateway.ipfs.io",
    "https://ipfs.infura.io",
    "https://infura-ipfs.io",
    "https://ninetailed.ninja",
    "https://10.via0.com",
    "https://ipfs.eternum.io",
    "https://hardbin.com",
    "https://gateway.blocksec.com",
    "https://cloudflare-ipfs.com",
    "https://astyanax.io",
    "https://cf-ipfs.com",
    "https://ipns.co",
    "https://ipfs.mrh.io",
    "https://gateway.originprotocol.com",
    "https://gateway.pinata.cloud",
    "https://ipfs.doolta.com",
    "https://ipfs.sloppyta.co",
    "https://ipfs.greyh.at",
    "https://gateway.serph.network",
    "https://jorropo.net",
    "https://gateway.temporal.cloud",
    "https://ipfs.fooock.com",
    "https://cdn.cwinfo.net",
    "https://aragon.ventures",
    "https://ipfs-cdn.aragon.ventures",
    "https://permaweb.io",
    "https://ipfs.stibarc.com",
    "https://ipfs.best-practice.se",
    "https://2read.net",
    "https://ipfs.2read.net",
    "https://storjipfs-gateway.com",
    "https://ipfs.runfission.com",
    "https://ipfs.trusti.id",
    "https://ipfs.overpi.com",
    "https://gateway.ipfs.lc",
    "https://ipfs.leiyun.org",
    "https://ipfs.ink",
    "https://ipfs.oceanprotocol.com",
    "https://d26g9c7mfuzstv.cloudfront.net",
    "https://ipfsgateway.makersplace.com",
    "https://gateway.ravenland.org",
    "https://ipfs.funnychain.co",
    "https://ipfs.telos.miami",
    "https://robotizing.net",
    "https://ipfs.mttk.net",
    "https://ipfs.fleek.co",
    "https://ipfs.jbb.one",
    "https://ipfs.yt",
    "https://jacl.tech",
    "https://hashnews.k1ic.com",
    "https://ipfs.vip",
    "https://ipfs.k1ic.com",
    "https://ipfs.drink.cafe",
    "https://ipfs.azurewebsites.net",
    "https://gw.ipfspin.com",
    "https://ipfs.kavin.rocks",
    "https://ipfs.denarius.io",
    "https://ipfs.mihir.ch",
    "https://bluelight.link",
    "https://crustwebsites.net",
    "http://3.211.196.68:8080",
    "https://ipfs0.sjc.cloudsigma.com",
    "https://ipfs-tezos.giganode.io",
    "http://183.252.17.149:82",
    "http://ipfs.genenetwork.org",
    "https://ipfs.eth.aragon.network",
    "https://ipfs.smartholdem.io",
    "https://bin.d0x.to",
    "https://ipfs.xoqq.ch",
    "http://natoboram.mynetgear.com:8080",
    "https://video.oneloveipfs.com",
    "http://ipfs.anonymize.com",
    "https://ipfs.noormohammed.tech",
    "https://ipfs.taxi",
    "https://ipfs.scalaproject.io",
    "https://search.ipfsgate.com",
    "https://ipfs.itargo.io",
    "https://ipfs.decoo.io",
    "https://ivoputzer.xyz",
    "https://alexdav.id",
    "https://ipfs.uploads.nu",
    "https://hub.textile.io",
    "https://ipfs1.pixura.io",
    "https://ravencoinipfs-gateway.com",
    "https://konubinix.eu",
    "https://ipfs.clansty.com",
    "https://3cloud.ee",
    "https://ipfs.tubby.cloud",
    "https://ipfs.lain.la",
    "https://ipfs.adatools.io",
    "https://ipfs.kaleido.art",
    "https://ipfs.slang.cx",
    "https://ipfs.arching-kaos.com",
    "https://storry.tv",
    "https://ipfs.kxv.io",
    "https://ipfs-nosub.stibarc.com",
    "https://ipfs.1-2.dev",
    "https://dweb.eu.org",
    "https://permaweb.eu.org",
    "https://ipfs.namebase.io",
    "https://ipfs.tribecap.co",
    "https://ipfs.kinematiks.com"
];

void loadBalancer(HTTPServerRequest req, HTTPServerResponse res)
{
    Mutex mtx = new Mutex();
    size_t idx;
    bool served;

    auto type = req.params["type"];
    if (type != "ipfs" && type != "ipns")
    {
        res.writeBody(format!"bad request: /%s/ is unsupported"(type), 400);
        return;
    }

    HTTPClientSettings csettings = new HTTPClientSettings;
    csettings.connectTimeout = 5.seconds;

    Future!bool[GATEWAY_LIST.length] asyncTasks;
    foreach(i, gw; GATEWAY_LIST)
    {
        if(served) return;

        auto running = asyncTasks[0..i].filter!(f => !f.ready).array;
        enum MAX_RUNNING = 4;
        if (running.length >= MAX_RUNNING)
            foreach (f; running[0..$-MAX_RUNNING])
                f.getResult();

        logInfo(format!"requesting %s"(gw));
        asyncTasks[i] = async({
            requestHTTP(format!"%s%s"(gw, req.requestURI),
                (scope creq) {
                    creq.method = creq.method;
                },
                (scope cres) {
                    mtx.lock();
                    scope(exit) mtx.unlock();
                    if (served) return;

                    switch(cres.statusCode)
                    {
                    case 200: .. case 299: // success
                        served = true;
                        res.statusCode = cres.statusCode;
                        res.writeBody(
                            cres.bodyReader.asInterface!InputStream,
                            cres.contentType);
                        served = true;
                        break;
                    case 300: .. case 399: // redirection
                        if ("Location" in cres.headers)
                        {
                            res.redirect(cres.headers["Location"]);
                            break;
                        }

                        res.writeBody("bad request on reverse proxy", 400);
                        break;
                    default: break;
                    }

                },
                csettings
            );

            return true;
        });
        sleep(300.msecs);
    }

    foreach(f; asyncTasks)
        f.getResult();
}

void main()
{
    auto router = new URLRouter;
    router.get("/:type/*", &loadBalancer);
    auto settings = new HTTPServerSettings;
    settings.port = 8888;
    listenHTTP(settings, router);
    runApplication();
}

