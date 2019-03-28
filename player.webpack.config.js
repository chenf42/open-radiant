const path = require('path');

const ReplaceInFileWebpackPlugin = require('replace-in-file-webpack-plugin');

const config = {

    // mode: 'development',
    mode: 'production',

    entry: path.join(__dirname, 'player.js'),

    output: {
      path: path.join(__dirname, '.'),
      filename: './player.bundle.js'
    },

    module: {
      noParse: [ /flat-surface-shader/, /src/, /build/ ],
      rules: [
        {
          test:    /\.elm$/,
          exclude: [ /elm-stuff/, /node_modules/, /build/ ],
          use: {
            // loader: "elm-webpack-loader?optimize=true"
            loader: "elm-webpack-loader"
          }
        },
        {
          test: /\.css$/,
          use: [ 'style-loader', 'css-loader' ]
        }
      ]
    },

    resolve: {
        extensions: ['.js']
    },

    plugins: [
      new ReplaceInFileWebpackPlugin([{
          files: ['player.bundle.js'],
          rules: [
            {
              search: /var e=n\.fragment/,
              replace: 'var e=n?n.fragment:{}'
            },
            {
              search: 'case 1:throw new Error("Browser.application programs cannot handle URLs like this:\\n\\n    "+document.location.href+"\\n\\nWhat is the root? The root of your file system? Try looking at this program with `elm reactor` or some other server.");case 2:',
              replace: 'case 2:'
            }
          ]
      }])
  ]

};

module.exports = config;
