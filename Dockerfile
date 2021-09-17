# To build from this, do something like:

#   docker build -t test/text-mapper .

# You can rebuild quickly, if things don't change.
# You can then run it with:

#   docker run test/text-mapper


FROM  perl:latest

RUN mkdir /app

RUN cpanm File::ShareDir::Install  

RUN cd /app && git clone https://github.com/kensanata/text-mapper.git

RUN cd /app/text-mapper && cpanm .

ENTRYPOINT ["/usr/local/bin/morbo", "--mode", "development", "--listen", "http://*:3010", "/app/text-mapper/script/text-mapper" ]
