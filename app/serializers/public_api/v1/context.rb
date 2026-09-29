module PublicApi
  module V1
    # What a serializer needs to know about the request: the release that
    # answers and the language of `cite` and caveat text.
    Context = Data.define(:release, :locale) do
      def fr? = locale == "fr"

      def pin(path) = Links.url(path, { "as_of" => release })

      # The data dictionary the release was built with.
      def dictionary = Catalog.dictionary(release)
    end
  end
end
